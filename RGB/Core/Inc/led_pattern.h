/**
  ******************************************************************************
  * @file    led_pattern.h
  * @brief   灯带图案表：按任意规律点亮指定灯珠
  ******************************************************************************
  * 用法：
  *   1. 在 led_pattern.c 顶部的"用户编辑区"写图案表
  *   2. main.c 里把 DEMO_MODE 设成 0
  *   3. 主循环里调用 LedPattern_Task()（非阻塞，不要加 HAL_Delay）
  *
  * 一个"画面"由若干"段"组成，每段描述一段灯珠的颜色：
  *   SEG(start, count, r, g, b)             从第 start 颗起连续 count 颗
  *   SEG_STEP(start, count, step, r,g,b)    从第 start 颗起每隔 step 颗亮一颗
  *   SEG_MASK(mask, r, g, b)                mask 的 bit i 对应第 i 颗灯珠
  *   SEG_OFF(start, count)                  这一段熄灭
  *
  * 同一画面里可以写多个段，后面的段覆盖前面的段，
  * 所以"先整条染红、再把第 5~9 颗改成蓝"这样叠加着写。
  ******************************************************************************
  */
#ifndef __LED_PATTERN_H
#define __LED_PATTERN_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

/** 一个段：描述一段灯珠的颜色。 */
typedef struct
{
  uint16_t start;   /* 起始灯珠序号 */
  uint16_t count;   /* 点亮几颗 */
  uint16_t step;    /* 相邻两颗的间隔，1 = 连续，2 = 隔一颗亮一颗 */
  uint32_t mask;    /* 非 0 时改用位掩码：bit i = 第 i 颗灯珠亮 */
  uint8_t  r;
  uint8_t  g;
  uint8_t  b;
} LedSeg;

/** 一个画面：保持多久 + 由哪些段组成。 */
typedef struct
{
  uint16_t      hold_ms;  /* 这个画面保持多少毫秒 */
  const LedSeg *segs;     /* 段数组 */
  uint8_t       nsegs;    /* 段的数量 */
} LedStep;

/* ---------------------------------------------------------------------------
 * 接口
 * -------------------------------------------------------------------------*/

/** 初始化图案播放器，立即显示第 0 个画面。 */
void LedPattern_Init(void);

/** 在主循环里反复调用。到达保持时间就切到下一个画面，不会阻塞。 */
void LedPattern_Task(void);

/** 从头开始播放。 */
void LedPattern_Restart(void);

/** 当前画面序号（从 0 开始）。 */
uint16_t LedPattern_Step(void);

/** 画面总数。 */
uint16_t LedPattern_Count(void);

#ifdef __cplusplus
}
#endif

#endif /* __LED_PATTERN_H */
