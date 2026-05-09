/**
 * 宠物的"日常活动"推断
 *  - 当前页面上下文（看视频 / 写代码 / 读长文 / 逛美食）
 *  - 时辰（早安 / 午饭 / 晚间剧 / 夜困）
 * 返回具体 PetState 之后交给 FSM 触发，配合 mood 气泡做差异化
 */

import type { PetState } from './pet';

export type SiteContext = 'video' | 'code' | 'news' | 'food' | 'social' | 'generic';

const VIDEO_HOSTS = /youtube\.com|youtu\.be|bilibili\.com|netflix\.com|twitch\.tv|iqiyi\.com|youku\.com|qq\.com\/v|douyin\.com|tiktok\.com|v\.qq\.com|mgtv\.com/i;
const CODE_HOSTS  = /github\.com|gitlab\.com|bitbucket\.org|stackoverflow\.com|codepen\.io|codesandbox\.io|developer\.mozilla\.org|docs\.|leetcode\.com|hackerrank\.com|juejin\.cn|csdn\.net/i;
const NEWS_HOSTS  = /zhihu\.com|medium\.com|substack\.com|36kr\.com|sspai\.com|jianshu\.com|infoq\.|news\.|cnn\.com|bbc\.|reuters\.com|theverge\.com|techcrunch\.com|nytimes\.com/i;
const FOOD_HOSTS  = /meituan\.com|ele\.me|xiachufang\.com|douguo\.com|xiangha\.com|food\.|recipe|meishichina\.com/i;
const SOCIAL_HOSTS= /twitter\.com|x\.com|weibo\.com|facebook\.com|instagram\.com|xiaohongshu\.com|xhs\.cn|reddit\.com/i;

export function detectContext(href: string = location.href): SiteContext {
  let host = '';
  try { host = new URL(href).hostname; } catch { return 'generic'; }
  if (VIDEO_HOSTS.test(host))  return 'video';
  if (CODE_HOSTS.test(host))   return 'code';
  if (FOOD_HOSTS.test(host))   return 'food';
  if (NEWS_HOSTS.test(host))   return 'news';
  if (SOCIAL_HOSTS.test(host)) return 'social';
  return 'generic';
}

export function contextToState(c: SiteContext): PetState | null {
  switch (c) {
    case 'video':  return 'watching';
    case 'code':   return 'working';
    case 'news':   return 'reading';
    case 'food':   return 'eating';
    default:       return null;
  }
}

/** 依据当前时辰推一个合适的状态，不触发频率太高——只在刚挂载和定时 check 时用 */
export function timeOfDayState(d: Date = new Date()): PetState | null {
  const hm = d.getHours() + d.getMinutes() / 60;
  if (hm >= 7 && hm < 9)        return 'greeting';
  if (hm >= 11.5 && hm < 13.5)  return 'eating';
  if (hm >= 18 && hm < 20)      return 'watching';
  if (hm >= 22 || hm < 6)       return 'sleepy';
  return null;
}

/** 从固定活动库里随机挑一个 "业余爱好" 状态，给 macro-tick 用 */
const HOBBY_POOL: PetState[] = ['dance', 'sing', 'exercise', 'reading', 'watching', 'eating'];
export function pickHobby(): PetState {
  return HOBBY_POOL[Math.floor(Math.random() * HOBBY_POOL.length)];
}
