/**
  ******************************************************************************
  * @file    led_pattern.c
  * @brief   灯带图案表播放器：按你写的表逐帧点亮指定灯珠
  ******************************************************************************
  * 你只需要改"用户编辑区"里的图案表，下面的实现不用动。
  ******************************************************************************
  */

#include "led_pattern.h"
#include "ws2812.h"
#include "main.h"

/*==============================================================================
 *                        ★ 用户编辑区：改这里 ★
 *============================================================================*/

/* ---------------------------------------------------------------------------
 * 段定义宏
 *
 *   SEG(起始, 颗数, R, G, B)            从第"起始"颗起连续点亮"颗数"颗
 *   SEG_STEP(起始, 颗数, 间隔, R, G, B) 每隔"间隔"颗亮一颗（2 = 隔一颗亮一颗）
 *   SEG_MASK(掩码, R, G, B)            掩码的 bit i 对应第 i 颗灯珠
 *   SEG_OFF(起始, 颗数)                 把这一段熄灭
 *
 * 同一画面里可以写多个段，后写的覆盖先写的。
 * -------------------------------------------------------------------------*/

#define SEG(s, c, r, g, b) \
  { (uint16_t)(s), (uint16_t)(c), 1u, 0u, (uint8_t)(r), (uint8_t)(g), (uint8_t)(b) }

#define SEG_STEP(s, c, st, r, g, b) \
  { (uint16_t)(s), (uint16_t)(c), (uint16_t)(st), 0u, (uint8_t)(r), (uint8_t)(g), (uint8_t)(b) }

#define SEG_MASK(m, r, g, b) \
  { 0u, 0u, 1u, (uint32_t)(m), (uint8_t)(r), (uint8_t)(g), (uint8_t)(b) }

#define SEG_OFF(s, c) \
  { (uint16_t)(s), (uint16_t)(c), 1u, 0u, 0u, 0u, 0u }

/* STEP(保持毫秒, 段表) —— 一个画面 */
#define STEP(hold, segs) \
  { (uint16_t)(hold), (segs), (uint8_t)(sizeof(segs) / sizeof((segs)[0])) }


/*==============================================================================
 *  ★★★ 就在这里写你的规律 ★★★
 *
 *  下面这套示例演示了几种常见写法，播放效果：
 *      全红 500ms -> 红蓝各半 500ms -> 中间亮黄 500ms -> 流星追尾 150ms x 8
 *
 *  想换成自己的，直接改段表和 pattern[] 即可。
 *============================================================================*/

/* --- 画面 1：整条红色 --- */
static const LedSeg segs_red[] =
{
  SEG(0, WS2812_LED_NUM, 255, 0, 0),
};

/* --- 画面 2：前一半红、后一半蓝（后写的段覆盖前面的） --- */
static const LedSeg segs_split[] =
{
  SEG(0, WS2812_LED_NUM, 255, 0, 0),                 /* 先整条红 */
  SEG(WS2812_LED_NUM / 2, WS2812_LED_NUM / 2, 0, 0, 255),  /* 后半改蓝 */
};

/* --- 画面 3：全灭 + 中间 4 颗黄色 --- */
static const LedSeg segs_middle[] =
{
  SEG_OFF(0, WS2812_LED_NUM),
  SEG(WS2812_LED_NUM / 2 - 2, 4, 255, 200, 0),
};

/* --- 画面 4：隔一颗亮一颗（斑马纹） --- */
static const LedSeg segs_zebra[] =
{
  SEG_OFF(0, WS2812_LED_NUM),
  SEG_STEP(0, WS2812_LED_NUM, 2, 0, 255, 128),
};

/* --- 画面 5~12：流星追尾，一颗亮点往前跑 --- */
static const LedSeg segs_comet0[] =
{
  SEG_OFF(0, WS2812_LED_NUM), SEG(0, 1, 255, 255, 255),
};
static const LedSeg segs_comet1[] =
{
  SEG_OFF(0, WS2812_LED_NUM), SEG(1, 1, 255, 255, 255),
};
static const LedSeg segs_comet2[] =
{
  SEG_OFF(0, WS2812_LED_NUM), SEG(2, 1, 255, 255, 255),
};
static const LedSeg segs_comet3[] =
{
  SEG_OFF(0, WS2812_LED_NUM), SEG(3, 1, 255, 255, 255),
};
static const LedSeg segs_comet4[] =
{
  SEG_OFF(0, WS2812_LED_NUM), SEG(4, 1, 255, 255, 255),
};
static const LedSeg segs_comet5[] =
{
  SEG_OFF(0, WS2812_LED_NUM), SEG(5, 1, 255, 255, 255),
};
static const LedSeg segs_comet6[] =
{
  SEG_OFF(0, WS2812_LED_NUM), SEG(6, 1, 255, 255, 255),
};
static const LedSeg segs_comet7[] =
{
  SEG_OFF(0, WS2812_LED_NUM), SEG(7, 1, 255, 255, 255),
};

/* --- 图案表：按顺序播放，播完回到第一个 --- */
static const LedStep pattern[] =
{
  STEP(500, segs_red),
  STEP(500, segs_split),
  STEP(500, segs_middle),
  STEP(500, segs_zebra),
  STEP(150, segs_comet0),
  STEP(150, segs_comet1),
  STEP(150, segs_comet2),
  STEP(150, segs_comet3),
  STEP(150, segs_comet4),
  STEP(150, segs_comet5),
  STEP(150, segs_comet6),
  STEP(150, segs_comet7),
};

/*==============================================================================
 *                    用户编辑区结束，下面是播放器实现
 *============================================================================*/

#define PATTERN_COUNT   (sizeof(pattern) / sizeof(pattern[0]))

/* Private variables ---------------------------------------------------------*/

static uint16_t s_step;       /* 当前画面序号 */
static uint32_t s_next_tick;  /* 下一个画面的切换时刻 */

/* Private functions ---------------------------------------------------------*/

/**
  * @brief  把第 step 个画面画到灯带缓冲并推送出去。
  */
static void LedPattern_Draw(uint16_t step)
{
  const LedStep *st = &pattern[step];

  /* 每帧都从全灭开始，避免上一帧的残留 */
  for (uint16_t i = 0; i < WS2812_LED_NUM; i++)
  {
    WS2812_SetPixel(i, 0, 0, 0);
  }

  for (uint8_t k = 0; k < st->nsegs; k++)
  {
    const LedSeg *sg = &st->segs[k];

    if (sg->mask != 0u)
    {
      /* 位掩码模式：bit i 对应第 i 颗灯珠 */
      for (uint16_t i = 0; i < WS2812_LED_NUM && i < 32u; i++)
      {
        if ((sg->mask & (1UL << i)) != 0UL)
        {
          WS2812_SetPixel(i, sg->r, sg->g, sg->b);
        }
      }
    }
    else
    {
      /* 范围模式：从 start 开始每 step 颗取一颗，共 count 颗 */
      uint16_t placed = 0;
      uint32_t idx = sg->start;
      uint32_t stride = (sg->step == 0u) ? 1u : sg->step;

      while (placed < sg->count && idx < WS2812_LED_NUM)
      {
        WS2812_SetPixel((uint16_t)idx, sg->r, sg->g, sg->b);
        idx += stride;
        placed++;
      }
    }
  }

  WS2812_Show();
}

/* Exported functions --------------------------------------------------------*/

void LedPattern_Init(void)
{
  s_step = 0u;
  LedPattern_Draw(0u);
  s_next_tick = HAL_GetTick() + pattern[0].hold_ms;
}

void LedPattern_Task(void)
{
  if ((int32_t)(HAL_GetTick() - s_next_tick) < 0)
  {
    return;
  }

  s_step++;
  if (s_step >= PATTERN_COUNT)
  {
    s_step = 0u;
  }

  LedPattern_Draw(s_step);

  s_next_tick += pattern[s_step].hold_ms;
}

void LedPattern_Restart(void)
{
  s_step = 0u;
  LedPattern_Draw(0u);
  s_next_tick = HAL_GetTick() + pattern[0].hold_ms;
}

uint16_t LedPattern_Step(void)
{
  return s_step;
}

uint16_t LedPattern_Count(void)
{
  return (uint16_t)PATTERN_COUNT;
}
