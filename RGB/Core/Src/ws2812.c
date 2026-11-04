/**
  ******************************************************************************
  * @file    ws2812.c
  * @brief   WS2812 / WS2812B 灯带驱动（TIM1_CH1 PWM + DMA1_Channel5）
  ******************************************************************************
  * 原理：
  *   WS2812 每个码元 1.25 us（800 kHz），用高电平宽度区分 0 和 1：
  *       '0'：高 0.4 us + 低 0.85 us
  *       '1'：高 0.8 us + 低 0.45 us
  *   把每个码元换算成 TIM1 的比较值（CCR1），一次性排进内存数组，
  *   由 DMA 在每个周期自动搬进 CCR1，CPU 不参与波形生成。
  *
  * 定时器配置：PSC=0，ARR = 定时器时钟 / 800 kHz - 1。
  * 72 MHz 时 ARR=89，T0H=29（403 ns），T1H=58（806 ns）。
  * 实际值在运行时按 HAL_RCC_GetPCLK2Freq() 现算，换主频不用改代码。
  *
  * 为什么用更新事件而不是 CC1 比较事件触发 DMA：
  *   比较事件在 CCR1=0 且计数器正好停在 0 时不保证产生，一旦漏掉第一次触发，
  *   整帧数据就会错位一位，所有灯珠颜色全乱。更新事件每个周期必然发生，
  *   没有这个隐患。
  *
  * 预装载带来的对齐：
  *   OC1PE 开启后，DMA 在更新事件写入的值要到下一个更新事件才真正生效，
  *   所以数据流前面会多出两拍低电平。这只是延长了帧首的复位低电平，
  *   不影响数据本身；收尾时也必须多等两拍，否则最后一个码元会被吃掉。
  ******************************************************************************
  */

#include "ws2812.h"
#include "main.h"

/* Private define ------------------------------------------------------------*/

/** 每颗灯珠 24 bit（G/R/B 各 8 bit）。 */
#define WS2812_BITS_PER_LED     24u

/** 数据后面补的零码元个数，用来凑出复位所需的低电平。
 *  1.25 us × 50 = 62.5 us，满足经典 WS2812B 的 >50 us 要求；
 *  帧与帧之间本来就有 WS2812_STEP_MS 的间隔，实际复位时间远大于这个值。 */
#define WS2812_RESET_SLOTS      50u

/** DMA 缓冲区长度（单位：码元）。 */
#define WS2812_DMA_BUF_LEN      (WS2812_LED_NUM * WS2812_BITS_PER_LED + WS2812_RESET_SLOTS)

/** 单帧 DMA 传输的超时保护（毫秒）。30 颗约 1 ms，留足余量。 */
#define WS2812_DMA_TIMEOUT_MS   20u

/* Private variables ---------------------------------------------------------*/

static TIM_HandleTypeDef s_htim;
static DMA_HandleTypeDef s_hdma;

/** 待发送的码元缓冲区，DMA 直接从这里搬运到 TIM1->CCR1。 */
static uint16_t s_dma_buf[WS2812_DMA_BUF_LEN];

/** 灯珠颜色缓冲，顺序为 R/G/B。 */
static uint8_t s_color[WS2812_LED_NUM][3];

/** '0' 码元的高电平计数值。 */
static uint16_t s_t0h;

/** '1' 码元的高电平计数值。 */
static uint16_t s_t1h;

/** 彩虹接力的当前步数，对 WS2812_LED_NUM 取模。 */
static uint32_t s_step;

/* Private function prototypes -----------------------------------------------*/

static void WS2812_BuildBuffer(void);
static void WS2812_HsvToRgb(uint16_t h, uint8_t s, uint8_t v,
                            uint8_t *r, uint8_t *g, uint8_t *b);

/* Private functions ---------------------------------------------------------*/

/**
  * @brief  把颜色缓冲编码成 WS2812 码元序列。
  * @note   WS2812 的数据顺序是 GRB，且高位先发。
  */
static void WS2812_BuildBuffer(void)
{
  uint32_t pos = 0;

  for (uint32_t i = 0; i < WS2812_LED_NUM; i++)
  {
    uint32_t grb = ((uint32_t)s_color[i][1] << 16)
                 | ((uint32_t)s_color[i][0] << 8)
                 |  (uint32_t)s_color[i][2];

    for (int32_t bit = 23; bit >= 0; bit--)
    {
      s_dma_buf[pos++] = ((grb & (1UL << bit)) != 0UL) ? s_t1h : s_t0h;
    }
  }

  while (pos < WS2812_DMA_BUF_LEN)
  {
    s_dma_buf[pos++] = 0u;
  }
}

/**
  * @brief  HSV 转 RGB。
  * @param  h 色相 0~359，s 饱和度 0~255，v 明度 0~255
  */
static void WS2812_HsvToRgb(uint16_t h, uint8_t s, uint8_t v,
                            uint8_t *r, uint8_t *g, uint8_t *b)
{
  uint8_t region;
  uint8_t remainder;
  uint8_t p;
  uint8_t q;
  uint8_t t;

  if (s == 0u)
  {
    *r = v;
    *g = v;
    *b = v;
    return;
  }

  region    = (uint8_t)(h / 60u);
  remainder = (uint8_t)(((h % 60u) * 255u) / 60u);

  p = (uint8_t)(((uint32_t)v * (255u - s)) >> 8);
  q = (uint8_t)(((uint32_t)v * (255u - (((uint32_t)s * remainder) >> 8))) >> 8);
  t = (uint8_t)(((uint32_t)v * (255u - (((uint32_t)s * (255u - remainder)) >> 8))) >> 8);

  switch (region)
  {
    case 0:  *r = v; *g = t; *b = p; break;
    case 1:  *r = q; *g = v; *b = p; break;
    case 2:  *r = p; *g = v; *b = t; break;
    case 3:  *r = p; *g = q; *b = v; break;
    case 4:  *r = t; *g = p; *b = v; break;
    default: *r = v; *g = p; *b = q; break;
  }
}

/* Exported functions --------------------------------------------------------*/

void WS2812_Init(void)
{
  GPIO_InitTypeDef  gpio = {0};
  TIM_OC_InitTypeDef oc  = {0};
  uint32_t pclk2;
  uint32_t timclk;
  uint32_t period;

  for (uint32_t i = 0; i < WS2812_LED_NUM; i++)
  {
    s_color[i][0] = 0u;
    s_color[i][1] = 0u;
    s_color[i][2] = 0u;
  }
  for (uint32_t i = 0; i < WS2812_DMA_BUF_LEN; i++)
  {
    s_dma_buf[i] = 0u;
  }
  s_step = 0u;

  /* --- 时钟 --- */
  __HAL_RCC_GPIOA_CLK_ENABLE();
  __HAL_RCC_TIM1_CLK_ENABLE();
  __HAL_RCC_DMA1_CLK_ENABLE();

  /* --- PA8 复用推挽输出（TIM1_CH1） --- */
  gpio.Pin   = GPIO_PIN_8;
  gpio.Mode  = GPIO_MODE_AF_PP;
  gpio.Speed = GPIO_SPEED_FREQ_HIGH;
  HAL_GPIO_Init(GPIOA, &gpio);

  /* --- 按实际定时器时钟换算码元宽度 ---
   * APB2 预分频为 1 时定时器时钟等于 PCLK2，否则是 PCLK2 的 2 倍。 */
  pclk2  = HAL_RCC_GetPCLK2Freq();
  timclk = (pclk2 == HAL_RCC_GetHCLKFreq()) ? pclk2 : (pclk2 * 2u);
  period = timclk / 800000u;
  if (period < 4u)
  {
    period = 4u;
  }

  /* 瞄准规格里的典型值 T0H = 0.35 us、T1H = 0.70 us，也就是码元周期的
   * 28% 和 56%，按 period 的比例算再四舍五入。
   *
   * 必须基于 period 而不是直接乘 timclk：72 MHz 时 timclk * 70 等于
   * 50.4 亿，超出 uint32 上限（42.9 亿）会静默回绕，算出来的 T1H 比 T0H
   * 还小，被下面的兜底改成 T0H+1，结果 '0' 和 '1' 的高电平几乎一样长，
   * 灯珠把每一位都读成 0，整条灯带全灭。period 只有几十，乘 56 不会溢出。
   *
   * 不取 0.40/0.80 us：老版 WS2812B 允许 T0H 到 0.55 us，但新版 WS2812B-V5
   * 的 T0H 上限是 0.38 us，0.40 us 已经踩线，会把 '0' 误判成 '1'。
   * 0.35/0.70 us 对两版芯片都在安全区中间。 */
  s_t0h = (uint16_t)((period * 28u + 50u) / 100u);
  s_t1h = (uint16_t)((period * 56u + 50u) / 100u);
  if (s_t0h == 0u)
  {
    s_t0h = 1u;
  }
  if (s_t1h <= s_t0h)
  {
    s_t1h = (uint16_t)(s_t0h + 1u);
  }
  if (s_t1h >= period)
  {
    s_t1h = (uint16_t)(period - 1u);
  }

  /* --- TIM1：800 kHz，PWM 模式 1，通道 1 --- */
  s_htim.Instance               = TIM1;
  s_htim.Init.Prescaler         = 0u;
  s_htim.Init.CounterMode       = TIM_COUNTERMODE_UP;
  s_htim.Init.Period            = period - 1u;
  s_htim.Init.ClockDivision     = TIM_CLOCKDIVISION_DIV1;
  s_htim.Init.RepetitionCounter = 0u;
  s_htim.Init.AutoReloadPreload = TIM_AUTORELOAD_PRELOAD_DISABLE;
  if (HAL_TIM_PWM_Init(&s_htim) != HAL_OK)
  {
    Error_Handler();
  }

  oc.OCMode     = TIM_OCMODE_PWM1;
  oc.Pulse      = 0u;
  oc.OCPolarity = TIM_OCPOLARITY_HIGH;
  oc.OCFastMode = TIM_OCFAST_DISABLE;
  if (HAL_TIM_PWM_ConfigChannel(&s_htim, &oc, TIM_CHANNEL_1) != HAL_OK)
  {
    Error_Handler();
  }

  /* --- DMA1 通道 5（固定映射到 TIM1_UP） ---
   * 用更新事件而不是 CC1 比较事件触发 DMA：比较事件在 CCR1=0 且计数器停在 0
   * 时不一定产生，一旦漏掉第一次触发整帧数据就会错位一位，全部灯珠颜色都乱。
   * 更新事件每个周期必然发生，没有这个隐患。 */
  s_hdma.Instance                 = DMA1_Channel5;
  s_hdma.Init.Direction           = DMA_MEMORY_TO_PERIPH;
  s_hdma.Init.PeriphInc           = DMA_PINC_DISABLE;
  s_hdma.Init.MemInc              = DMA_MINC_ENABLE;
  s_hdma.Init.PeriphDataAlignment = DMA_PDATAALIGN_HALFWORD;
  s_hdma.Init.MemDataAlignment    = DMA_MDATAALIGN_HALFWORD;
  s_hdma.Init.Mode                = DMA_NORMAL;
  s_hdma.Init.Priority            = DMA_PRIORITY_HIGH;
  if (HAL_DMA_Init(&s_hdma) != HAL_OK)
  {
    Error_Handler();
  }
  __HAL_LINKDMA(&s_htim, hdma[TIM_DMA_ID_UPDATE], s_hdma);

  /* 启动 PWM 输出：使能 CC1 通道、MOE 和计数器。
   * 之后计数器一直自由运行，刷新时只重装 DMA，不再动定时器。 */
  if (HAL_TIM_PWM_Start(&s_htim, TIM_CHANNEL_1) != HAL_OK)
  {
    Error_Handler();
  }

  /* 初始化完先发一帧全灭，避免上电时灯带残留随机颜色 */
  WS2812_Show();
}

void WS2812_SetPixel(uint16_t index, uint8_t r, uint8_t g, uint8_t b)
{
  if (index >= WS2812_LED_NUM)
  {
    return;
  }

  s_color[index][0] = r;
  s_color[index][1] = g;
  s_color[index][2] = b;
}

void WS2812_Show(void)
{
  WS2812_BuildBuffer();

  /* 输出先拉低，并把计数器归零，让帧从完整的码元周期边界开始 */
  __HAL_TIM_SET_COMPARE(&s_htim, TIM_CHANNEL_1, 0u);
  __HAL_TIM_SET_COUNTER(&s_htim, 0u);

  /* 清掉可能已经挂起的事件标志。若 UIF 在使能 DMA 请求前就是 1，
   * 硬件可能立刻补发一次请求，导致整帧错位一位。 */
  __HAL_TIM_CLEAR_FLAG(&s_htim, TIM_FLAG_UPDATE | TIM_FLAG_CC1);

  /* 直接寄存器装载，绕开 HAL DMA 状态机：F1 HAL 的 PollForTransfer
   * 超时后会把句柄钉在 TIMEOUT 态，后续 HAL_DMA_Start 全部直接返回，
   * 通道悬挂在 EN=1/CNDTR=0 上再也起不来。这里每帧都把通道拉回
   * 确定状态，无论上一帧是正常完成还是半途卡死。 */
  DMA1_Channel5->CCR   &= (uint16_t)~DMA_CCR_EN;
  DMA1->IFCR           =  DMA_IFCR_CGIF5;
  DMA1_Channel5->CPAR  =  (uint32_t)&TIM1->CCR1;
  DMA1_Channel5->CMAR  =  (uint32_t)s_dma_buf;
  DMA1_Channel5->CNDTR =  WS2812_DMA_BUF_LEN;
  DMA1_Channel5->CCR   =  DMA_CCR_PL_1 | DMA_CCR_MSIZE_0 | DMA_CCR_PSIZE_0 |
                          DMA_CCR_MINC  | DMA_CCR_DIR      | DMA_CCR_EN;

  __HAL_TIM_ENABLE_DMA(&s_htim, TIM_DMA_UPDATE);

  /* 自轮询 TCIF。30 颗约 1 ms，20 ms 容限足够；超时也强制收尾，
   * 不让悬挂的通道卡住主循环。 */
  uint32_t t0 = HAL_GetTick();
  while ((DMA1->ISR & DMA_ISR_TCIF5) == 0u)
  {
    if ((HAL_GetTick() - t0) >= WS2812_DMA_TIMEOUT_MS)
    {
      break;
    }
  }

  __HAL_TIM_DISABLE_DMA(&s_htim, TIM_DMA_UPDATE);
  DMA1_Channel5->CCR &= (uint16_t)~DMA_CCR_EN;

  /* 收尾把比较值清零，让数据线保持低电平。
   * 缓冲区末尾的 WS2812_RESET_SLOTS 个零码元保证最后一个真实数据位
   * 早已输出完毕，这里不需要额外等待。 */
  __HAL_TIM_SET_COMPARE(&s_htim, TIM_CHANNEL_1, 0u);
}

void WS2812_Clear(void)
{
  for (uint32_t i = 0; i < WS2812_LED_NUM; i++)
  {
    s_color[i][0] = 0u;
    s_color[i][1] = 0u;
    s_color[i][2] = 0u;
  }

  WS2812_Show();
}

void WS2812_RainbowStep(void)
{
  for (uint32_t i = 0; i < WS2812_LED_NUM; i++)
  {
    uint8_t r;
    uint8_t g;
    uint8_t b;

    /* 第 i 颗的色相 = (i + 当前步数) 在色环上的位置。
     * 每走一步，每颗灯珠都拿到前一颗上一步的颜色，
     * 看上去就是整条彩虹往序号大的方向挪了一格。 */
    uint16_t hue = (uint16_t)((((uint32_t)i + s_step) * 360u / WS2812_LED_NUM) % 360u);

    WS2812_HsvToRgb(hue, WS2812_SAT, WS2812_VAL, &r, &g, &b);
    WS2812_SetPixel((uint16_t)i, r, g, b);
  }

  WS2812_Show();

  s_step++;
  if (s_step >= WS2812_LED_NUM)
  {
    s_step = 0u;
  }
}
