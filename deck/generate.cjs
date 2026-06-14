/* Next 路演 PPT — 严格按参考图风格（紫色主调 + 蓝/紫/绿序列 + 居中封面 + 彩色左边栏卡 +
   数字圆徽 + 堆叠描边架构 + 淡紫 footnote + 左下 Slide NN）。内容据 PITCH-10min(1).md。
   node deck/generate.cjs → deck/Next.pptx */
const pptxgen = require("pptxgenjs");

const C = {
  bg: "08080A", card: "15151C", line: "2A2A33", tint: "15122A",
  text: "F4F4F6", mut: "A0A0A8", dim: "5E5E68",
  pur: "7C5CFF", blu: "5B8DEF", grn: "3FD18B", red: "FF6B61", yel: "FFB23E", pnk: "FF5C8A",
};
const SEQ = [C.blu, C.pur, C.grn, C.blu, C.grn];
const F_ZH = "PingFang SC", F_EN = "Helvetica Neue";

const pres = new pptxgen();
pres.defineLayout({ name: "W", width: 13.333, height: 7.5 });
pres.layout = "W";
pres.author = "Next"; pres.title = "Next — 刘海，是你的下一件事";
const W = 13.333, H = 7.5, MX = 0.92;
let page = 0;
const rr = 0.09;
const shadow = () => ({ type: "outer", color: "000000", blur: 12, offset: 4, angle: 90, opacity: 0.4 });

function base(s) { s.background = { color: C.bg }; }
function foot(s) {
  page += 1;
  s.addText(`Slide ${String(page).padStart(2, "0")}`, { x: MX, y: H - 0.55, w: 3, h: 0.3, fontFace: F_EN, fontSize: 10.5, color: "B9B9C2" });
  s.addText(String(page).padStart(2, "0"), { x: W - 1.6 - MX, y: H - 0.62, w: 1.6, h: 0.3, fontFace: F_EN, fontSize: 11, color: C.dim, align: "right" });
}
const kicker = (s, t, c = C.pur) => s.addText(t, { x: MX, y: 0.62, w: 9, h: 0.34, fontFace: F_ZH, fontSize: 13, color: c, charSpacing: 2, bold: true });
const title = (s, t, sz = 34) => s.addText(t, { x: MX, y: 1.0, w: W - 2 * MX, h: 1.0, fontFace: F_ZH, fontSize: sz, color: C.text, bold: true, valign: "top", lineSpacingMultiple: 1.05 });
const sub = (s, t, y = 1.78) => s.addText(t, { x: MX, y, w: W - 2 * MX, h: 0.5, fontFace: F_ZH, fontSize: 15.5, color: C.mut, lineSpacingMultiple: 1.25, valign: "top" });
function footnote(s, lines, y = 6.0) {
  const arr = Array.isArray(lines) ? lines : [lines];
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: MX, y, w: W - 2 * MX, h: 0.36 + arr.length * 0.3, fill: { color: C.tint }, line: { color: "2C2550", width: 1 }, rectRadius: 0.06 });
  s.addText(arr.map((t, i) => ({ text: t, options: { breakLine: i < arr.length - 1 } })), { x: MX + 0.35, y: y + 0.06, w: W - 2 * MX - 0.7, h: 0.3 + arr.length * 0.3, fontFace: F_ZH, fontSize: 13, color: C.mut, lineSpacingMultiple: 1.3, valign: "middle" });
}
function seqCard(s, { x, y, w, h, n, color, head, desc }) {
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w, h, fill: { color: C.card }, line: { color: C.line, width: 1 }, rectRadius: rr, shadow: shadow() });
  s.addShape(pres.shapes.RECTANGLE, { x, y: y + 0.12, w: 0.07, h: h - 0.24, fill: { color } });
  s.addText(n, { x: x + 0.34, y: y + 0.26, w: w - 0.6, h: 0.55, fontFace: F_EN, fontSize: 26, color, bold: true });
  s.addText(head, { x: x + 0.34, y: y + 0.82, w: w - 0.6, h: 0.5, fontFace: F_ZH, fontSize: 18, color: C.text, bold: true });
  if (desc) s.addText(desc, { x: x + 0.34, y: y + 1.32, w: w - 0.62, h: h - 1.55, fontFace: F_ZH, fontSize: 12.5, color: C.mut, lineSpacingMultiple: 1.3, valign: "top" });
}
const arrowR = (s, x, y) => s.addText("→", { x, y, w: 0.5, h: 0.5, fontFace: F_EN, fontSize: 22, color: C.dim, align: "center" });
function bulletNum(s, n, text, y) {
  s.addShape(pres.shapes.OVAL, { x: MX, y, w: 0.42, h: 0.42, fill: { color: C.pur } });
  s.addText(String(n), { x: MX, y, w: 0.42, h: 0.42, fontFace: F_EN, fontSize: 15, color: "FFFFFF", bold: true, align: "center", valign: "middle" });
  s.addText(text, { x: MX + 0.62, y: y - 0.02, w: W - MX - 0.62 - MX, h: 0.46, fontFace: F_ZH, fontSize: 17, color: C.text, valign: "middle" });
}

/* 1 · 封面（居中） */
(() => {
  const s = pres.addSlide(); base(s); foot(s);
  s.addShape(pres.shapes.RECTANGLE, { x: 0, y: 0, w: W, h: 0.05, fill: { color: C.pur } });
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: W / 2 - 1.0, y: 0.7, w: 2.0, h: 0.5, fill: { color: C.card }, line: { color: C.pur, width: 1 }, rectRadius: 0.1 });
  s.addText("Next", { x: W / 2 - 1.0, y: 0.7, w: 2.0, h: 0.5, fontFace: F_EN, fontSize: 15, color: C.pur, bold: true, align: "center", valign: "middle" });
  s.addText("刘海，是你的下一件事", { x: 0, y: 2.75, w: W, h: 1.1, fontFace: F_ZH, fontSize: 52, color: C.text, bold: true, align: "center" });
  s.addText("住在 Mac 刘海里的 AI 任务管家", { x: 0, y: 3.95, w: W, h: 0.5, fontFace: F_ZH, fontSize: 19, color: C.mut, align: "center" });
  s.addShape(pres.shapes.RECTANGLE, { x: W / 2 - 0.4, y: 4.7, w: 0.8, h: 0.03, fill: { color: C.pur } });
  s.addText("3 人小队 · 48 小时 · Hackathon 2026", { x: 0, y: 5.0, w: W, h: 0.4, fontFace: F_ZH, fontSize: 14, color: C.dim, align: "center" });
  s.addText("10 分钟，现场演给你看", { x: 0, y: 6.3, w: W, h: 0.4, fontFace: F_ZH, fontSize: 13, color: C.dim, align: "center" });
})();

/* 2 · 痛点 */
(() => {
  const s = pres.addSlide(); base(s); foot(s);
  kicker(s, "痛点");
  title(s, "待办散落六七个工具，AI agent 还要盯终端", 30);
  const wins = [["微信", C.grn], ["邮件", C.blu], ["Jira", C.yel], ["日历", C.red], ["IDE", C.pur], ["终端 AI", C.pnk]];
  wins.forEach(([name, dot], i) => {
    const x = MX + 0.1 + i * 1.28, y = 2.0 + (i % 2) * 0.32;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w: 2.2, h: 1.55, fill: { color: i % 2 ? "121218" : "17171F" }, line: { color: C.line, width: 1 }, rectRadius: 0.07, shadow: shadow() });
    s.addShape(pres.shapes.OVAL, { x: x + 0.22, y: y + 0.24, w: 0.13, h: 0.13, fill: { color: dot } });
    s.addText(name, { x: x + 0.45, y: y + 0.16, w: 1.5, h: 0.3, fontFace: F_ZH, fontSize: 12, color: C.mut });
    [0.62, 0.92, 1.18].forEach((ly, k) => s.addShape(pres.shapes.RECTANGLE, { x: x + 0.22, y: y + ly, w: 1.7 - k * 0.3, h: 0.07, fill: { color: "26262F" } }));
  });
  const p = [
    "录入门槛高 — 90% 的事在「想记」和「真记」之间被忘掉",
    "提醒一闪而过 — 没有余光可感知的紧急度",
    "早上开机要开一堆窗口才知道今天干嘛",
  ];
  p.forEach((t, i) => bulletNum(s, i + 1, t, 4.55 + i * 0.66));
})();

/* 3 · 解法/定位 */
(() => {
  const s = pres.addSlide(); base(s); foot(s);
  kicker(s, "解法");
  title(s, "把一直空着的刘海，变成第二块屏", 32);
  sub(s, "不是又一个待办清单——一个永远在线的 AI 助手：收缩态只占两翼不挡内容，悬停展开、移开收回，余光就知急不急。", 1.78);
  const loop = [["记录", C.blu], ["追踪", C.pur], ["提醒", C.grn], ["复盘", C.blu]];
  loop.forEach(([t, c], i) => {
    const x = MX + i * 3.0;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y: 3.5, w: 2.5, h: 1.5, fill: { color: C.card }, line: { color: c, width: 1 }, rectRadius: rr });
    s.addText(t, { x, y: 3.5, w: 2.5, h: 1.5, fontFace: F_ZH, fontSize: 22, color: C.text, bold: true, align: "center", valign: "middle" });
    if (i < 3) s.addText("→", { x: x + 2.52, y: 3.95, w: 0.48, h: 0.5, fontFace: F_EN, fontSize: 22, color: C.pur, align: "center" });
  });
  footnote(s, "记录、追踪、提醒、复盘，全在这一小块闭环。", 5.5);
})();

/* 4 · 五大概念 */
(() => {
  const s = pres.addSlide(); base(s); foot(s);
  kicker(s, "核心理念");
  title(s, "按「你和它的关系」重新归类，零重叠", 30);
  sub(s, "一天里所有要你操心的东西，按关系分五类——其中要 review 的，是 AI agent 的会话。");
  const cc = [["Todo", "要做完", C.blu], ["WorkItem", "要推进", C.pur], ["Calendar", "要参加", C.grn], ["Message", "要读", C.blu], ["AgentSession", "要 review", C.pur]];
  const cw = 2.16, gap = 0.18;
  cc.forEach(([n, r, c], i) => {
    const x = MX + i * (cw + gap), hi = i === 4;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y: 3.2, w: cw, h: 2.5, fill: { color: hi ? C.pur : C.card }, line: { color: hi ? C.pur : C.line, width: 1 }, rectRadius: rr, shadow: shadow() });
    if (!hi) s.addShape(pres.shapes.RECTANGLE, { x, y: 3.32, w: 0.07, h: 2.26, fill: { color: c } });
    s.addText(n, { x: x + 0.26, y: 3.5, w: cw - 0.45, h: 0.8, fontFace: F_EN, fontSize: hi ? 15 : 16, color: hi ? "FFFFFF" : C.text, bold: true, valign: "top", lineSpacingMultiple: 1 });
    s.addText(r, { x: x + 0.26, y: 4.85, w: cw - 0.45, h: 0.5, fontFace: F_ZH, fontSize: 16, color: hi ? "FFFFFF" : c, bold: true });
  });
  footnote(s, "记住最后这个：它既是产品的一块，也正是我们这 48 小时的工作方式。", 6.0);
})();

/* 5 · Demo① 截图秒变待办 */
(() => {
  const s = pres.addSlide(); base(s); foot(s);
  kicker(s, "DEMO ①");
  title(s, "截图秒变结构化待办", 32);
  sub(s, "F2 截图 → AI 解析 → 3 秒生成待办，零录入", 1.78);
  const st = [["01", "截图", "F2 快捷键"], ["02", "AI 解析", "视觉识别 + 理解"], ["03", "待办生成", "标题 / 优先级 / 截止"]];
  st.forEach(([n, h, d], i) => {
    const x = MX + i * 3.95;
    seqCard(s, { x, y: 2.5, w: 3.55, h: 2.1, n, color: SEQ[i], head: h, desc: d });
    if (i < 2) arrowR(s, x + 3.57, 3.3);
  });
  footnote(s, ["AI 自动判断优先级（P0/P1/P2）、建议截止时间、挂原图可点开", "识别失败会如实告知，不瞎编"], 5.2);
})();

/* 6 · Demo② 一屏管全部工作流 */
(() => {
  const s = pres.addSlide(); base(s); foot(s);
  kicker(s, "DEMO ②");
  title(s, "一屏管全部工作流", 32);
  const t = [
    ["Today", C.blu, "今日该关注的事，AI 给建议工作顺序"],
    ["Work", C.pur, "Jira 工单 + GitHub PR，新分配降落卡可跳转"],
    ["Calendar", C.grn, "事件 / 提醒 / 个人任务并到一条时间线"],
    ["Inbox", C.blu, "邮件 + @我的 Jira/Confluence，收成一句话"],
  ];
  t.forEach(([h, c, d], i) => {
    const x = MX + (i % 2) * 5.95, y = 2.2 + Math.floor(i / 2) * 1.65;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w: 5.55, h: 1.45, fill: { color: C.card }, line: { color: C.line, width: 1 }, rectRadius: rr, shadow: shadow() });
    s.addShape(pres.shapes.RECTANGLE, { x, y: y + 0.12, w: 0.07, h: 1.21, fill: { color: c } });
    s.addText(h, { x: x + 0.34, y: y + 0.22, w: 5, h: 0.4, fontFace: F_EN, fontSize: 18, color: C.text, bold: true });
    s.addText(d, { x: x + 0.34, y: y + 0.7, w: 5, h: 0.5, fontFace: F_ZH, fontSize: 13, color: C.mut, valign: "top" });
  });
  footnote(s, "提醒分四级辉光、余光就知急不急；高优「提前准备」不自动消失，留徽章直到你处理。", 5.7);
})();

/* 7 · Demo③ Agent 会话监控 */
(() => {
  const s = pres.addSlide(); base(s); foot(s);
  kicker(s, "DEMO ③");
  title(s, "给写代码的人：Agent 会话监控", 30);
  sub(s, "AI agent 越来越多，但你得盯着终端。Next 把 agent 状态搬上刘海。");
  const fl = [["运行中徽章", C.blu], ["待确认橙铃铛", C.yel], ["完成弹卡", C.grn], ["跳回终端", C.pur]];
  fl.forEach(([t, c], i) => {
    const x = MX + i * 2.95;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y: 3.1, w: 2.6, h: 1.3, fill: { color: C.card }, line: { color: c, width: 1 }, rectRadius: rr });
    s.addText(t, { x: x + 0.15, y: 3.1, w: 2.3, h: 1.3, fontFace: F_ZH, fontSize: 15, color: C.text, bold: true, valign: "middle" });
    if (i < 3) s.addText("→", { x: x + 2.6, y: 3.5, w: 0.42, h: 0.5, fontFace: F_EN, fontSize: 20, color: C.pur, align: "center" });
  });
  footnote(s, ["运行中 / 待确认实时计数 · 子任务完成不打扰，只整轮结束才提示", "跳回 Terminal / iTerm / tmux pane · Claude Code 与 opencode 都支持"], 5.0);
})();

/* 8 · AI 晨晚报 + 高光 */
(() => {
  const s = pres.addSlide(); base(s); foot(s);
  kicker(s, "AI 晨晚报");
  title(s, "晨报排程、晚报复盘，清零有仪式感", 30);
  seqCard(s, { x: MX, y: 2.4, w: 5.55, h: 2.0, n: "AM", color: C.pur, head: "早报 · 今天先做什么", desc: "今日优先 / 会议 / 工单，建议工作顺序自动避开会议时段。" });
  seqCard(s, { x: MX + 5.95, y: 2.4, w: 5.55, h: 2.0, n: "PM", color: C.yel, head: "晚报 · 复盘今天 · 预警明天", desc: "完成与结转一目了然，明天的高优先级提前点出来。" });
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: MX, y: 4.7, w: W - 2 * MX, h: 1.2, fill: { color: C.card }, line: { color: C.grn, width: 1 }, rectRadius: rr });
  s.addText("今天全部清零 → 全屏烟花，刘海戴上皇冠", { x: MX, y: 4.7, w: W - 2 * MX, h: 1.2, fontFace: F_ZH, fontSize: 20, color: C.text, bold: true, align: "center", valign: "middle" });
})();

/* 9 · AI 用在哪 */
(() => {
  const s = pres.addSlide(); base(s); foot(s);
  kicker(s, "AI 融合");
  title(s, "AI 不是贴标签，在每个环节干活", 30);
  const ai = [
    ["截图视觉解析", C.blu], ["紧急度判断", C.pur], ["邮件一句话摘要", C.grn],
    ["晨报排程", C.blu], ["晚报复盘", C.pur], ["Today 多源建议", C.grn],
  ];
  ai.forEach(([h, c], i) => {
    const x = MX + (i % 3) * 3.95, y = 2.5 + Math.floor(i / 3) * 1.5;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w: 3.55, h: 1.25, fill: { color: C.card }, line: { color: C.line, width: 1 }, rectRadius: rr, shadow: shadow() });
    s.addShape(pres.shapes.OVAL, { x: x + 0.3, y: y + 0.45, w: 0.16, h: 0.16, fill: { color: c } });
    s.addText(h, { x: x + 0.62, y: y, w: 2.8, h: 1.25, fontFace: F_ZH, fontSize: 16, color: C.text, bold: true, valign: "middle" });
  });
  footnote(s, "Today 这条建议——综合待办 / 工单 / 会议多源给结论。", 5.65);
})();

/* 10 · 更多打磨 */
(() => {
  const s = pres.addSlide(); base(s); foot(s);
  kicker(s, "打磨");
  title(s, "还有一堆体验打磨，让产品真正可用", 30);
  const pol = [["语音速记 ⌥Space", "一句话录入"], ["四级分级辉光", "余光感知急不急"], ["勿扰时段", "该静的时候静"], ["Mock 兜底", "不配 Jira/邮件/AI 也能用"]];
  pol.forEach(([h, d], i) => {
    const x = MX + (i % 2) * 5.95, y = 2.6 + Math.floor(i / 2) * 1.55;
    seqCard(s, { x, y, w: 5.55, h: 1.3, n: `0${i + 1}`, color: SEQ[i], head: h, desc: d });
  });
})();

/* 11 · vibecoding（重头） */
(() => {
  const s = pres.addSlide(); base(s); foot(s);
  kicker(s, "实现过程 · VIBECODING ★");
  title(s, "我们怎么 review AI agent 的代码，造出 Next", 26);
  s.addText("回到第五个概念——AgentSession = 要 review。这 48 小时，我们干的就是 review 一堆 AI 写的代码：用要解决的工作方式，造出了这个产品。",
    { x: MX, y: 1.7, w: W - 2 * MX, h: 0.6, fontFace: F_ZH, fontSize: 13.5, color: C.mut, lineSpacingMultiple: 1.25, valign: "top" });
  const pipe = ["需求", "openspec spec", "AI 实现", "swift build", "人 review", "合并"];
  pipe.forEach((t, i) => {
    const x = MX + i * 1.96;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y: 2.55, w: 1.72, h: 0.6, fill: { color: i === 4 ? C.pur : C.card }, line: { color: i === 4 ? C.pur : C.line, width: 1 }, rectRadius: 0.07 });
    s.addText(t, { x: x + 0.04, y: 2.55, w: 1.64, h: 0.6, fontFace: F_ZH, fontSize: 11.5, color: i === 4 ? "FFFFFF" : C.text, bold: true, align: "center", valign: "middle" });
    if (i < 5) s.addText("›", { x: x + 1.7, y: 2.58, w: 0.26, h: 0.5, fontFace: F_EN, fontSize: 18, color: C.dim, align: "center" });
  });
  const dim = [
    ["广度", C.blu, "代码 / 调试 / 测试 / 文档 / commit / CI 修复，全程 AI 参与"],
    ["高级技巧", C.pur, "openspec spec-driven、context7 查文档、taste skill 打磨 UI、CODING_GUIDELINES 当硬规则、多 agent 靠 git+spec 协调"],
    ["参与关键决策", C.grn, "状态机 + 单一数据源架构、五大概念模型，和 AI 反复 brainstorm 定下来"],
    ["验证与修正", C.blu, "外部服务先写 Mock 兜底；AI 改完必过 swift build + Debug 冒烟，再人工 review"],
  ];
  dim.forEach(([h, c, d], i) => {
    const x = MX + (i % 2) * 5.95, y = 3.5 + Math.floor(i / 2) * 1.55;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w: 5.55, h: 1.4, fill: { color: C.card }, line: { color: C.line, width: 1 }, rectRadius: rr });
    s.addShape(pres.shapes.RECTANGLE, { x, y: y + 0.12, w: 0.07, h: 1.16, fill: { color: c } });
    s.addText(h, { x: x + 0.32, y: y + 0.16, w: 5, h: 0.38, fontFace: F_ZH, fontSize: 15, color: c, bold: true });
    s.addText(d, { x: x + 0.32, y: y + 0.56, w: 5.1, h: 0.78, fontFace: F_ZH, fontSize: 11.8, color: C.mut, lineSpacingMultiple: 1.22, valign: "top" });
  });
})();

/* 12 · 技术方案（堆叠描边 + ↓） */
(() => {
  const s = pres.addSlide(); base(s); foot(s);
  kicker(s, "技术方案");
  title(s, "状态机驱动 + 单一数据源 + Swift 6 严格并发", 28);
  const layers = [
    ["IslandState 状态机", C.pur, "收缩态 ↔ 展开态 ↔ 通知态 ↔ 加载态 · 驱动刘海形变与动画", false],
    ["AppStore 单一数据源", C.blu, "所有状态集中管理 · Todo / WorkItem / Calendar / Message / AgentSession 统一存取", false],
    ["6 个服务协议 · 真实集成", C.grn, "", true],
  ];
  let y = 2.15;
  layers.forEach(([h, c, d, hasChips], i) => {
    const ht = hasChips ? 1.4 : 0.85;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: MX, y, w: W - 2 * MX, h: ht, fill: { color: "0E0E14" }, line: { color: c, width: 1.25 }, rectRadius: rr });
    s.addText(h, { x: MX + 0.32, y: y + 0.18, w: 8, h: 0.4, fontFace: F_ZH, fontSize: 16, color: c, bold: true });
    if (d) s.addText(d, { x: MX + 0.32, y: y + 0.56, w: W - 2 * MX - 0.6, h: 0.35, fontFace: F_ZH, fontSize: 12.5, color: C.mut });
    if (hasChips) {
      const chips = ["Jira", "GitHub", "EventKit", "IMAP/Graph", "Claude Code", "opencode"];
      chips.forEach((t, k) => {
        const cx = MX + 4.0 + (k % 3) * 2.4, cy = y + 0.5 + Math.floor(k / 3) * 0.5;
        s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: cx, y: cy, w: 2.2, h: 0.42, fill: { color: C.card }, line: { color: C.line, width: 1 }, rectRadius: 0.05 });
        s.addText(t, { x: cx, y: cy, w: 2.2, h: 0.42, fontFace: F_EN, fontSize: 12, color: C.text, bold: true, align: "center", valign: "middle" });
      });
    }
    if (i < 2) s.addText("↓", { x: W / 2 - 0.25, y: y + ht - 0.04, w: 0.5, h: 0.3, fontFace: F_EN, fontSize: 18, color: C.dim, align: "center" });
    y += ht + 0.26;
  });
  footnote(s, "不是 demo ware — 能装能用的 .app · Swift 6 严格并发 · 真实 OAuth 集成", 5.95);
})();

/* 13 · MCP 扩展 */
(() => {
  const s = pres.addSlide(); base(s); foot(s);
  kicker(s, "扩展点 · MCP");
  title(s, "Next 作为平台：MCP Server 让 agent 写入刘海", 28);
  sub(s, "现在已经能「读」agent 状态，下一步开放 MCP server，让任何 agent / 脚本 / CI 直接往 Next 写提醒和待办。");
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: MX, y: 3.6, w: 3.9, h: 1.3, fill: { color: C.card }, line: { color: C.line, width: 1 }, rectRadius: rr });
  s.addText("你的 Agent / 脚本 / CI", { x: MX, y: 3.6, w: 3.9, h: 1.3, fontFace: F_ZH, fontSize: 16, color: C.text, bold: true, align: "center", valign: "middle" });
  s.addText("→", { x: MX + 3.95, y: 3.95, w: 0.5, h: 0.5, fontFace: F_EN, fontSize: 24, color: C.dim, align: "center" });
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: MX + 4.6, y: 3.95, w: 1.7, h: 0.6, fill: { color: C.pur }, rectRadius: 0.08 });
  s.addText("MCP", { x: MX + 4.6, y: 3.95, w: 1.7, h: 0.6, fontFace: F_EN, fontSize: 15, color: "FFFFFF", bold: true, align: "center", valign: "middle", charSpacing: 2 });
  s.addText("→", { x: MX + 6.4, y: 3.95, w: 0.5, h: 0.5, fontFace: F_EN, fontSize: 24, color: C.dim, align: "center" });
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: MX + 7.0, y: 3.6, w: 3.9, h: 1.3, fill: { color: "0E0E14" }, line: { color: C.pur, width: 1.25 }, rectRadius: rr });
  s.addText("Next · 刘海弹提醒 / 待办", { x: MX + 7.0, y: 3.6, w: 3.9, h: 1.3, fontFace: F_ZH, fontSize: 16, color: C.text, bold: true, align: "center", valign: "middle" });
  footnote(s, "从「读」agent 状态，到让它能「写」——Next 变成你所有 agent 的统一提醒出口。（写入为下一步，非已完成）", 5.9);
})();

/* 14 · 收尾（居中） */
(() => {
  const s = pres.addSlide(); base(s); foot(s);
  s.addShape(pres.shapes.RECTANGLE, { x: 0, y: 0, w: W, h: 0.05, fill: { color: C.pur } });
  s.addText("让每个 Mac 用户的刘海里\n都住着一个 AI 任务管家", { x: 0, y: 2.6, w: W, h: 2.0, fontFace: F_ZH, fontSize: 40, color: C.text, bold: true, align: "center", lineSpacingMultiple: 1.15, valign: "top" });
  s.addShape(pres.shapes.RECTANGLE, { x: W / 2 - 0.4, y: 4.85, w: 0.8, h: 0.03, fill: { color: C.pur } });
  s.addText("Next · 刘海，是你的下一件事", { x: 0, y: 5.15, w: W, h: 0.4, fontFace: F_ZH, fontSize: 16, color: C.mut, align: "center" });
  s.addText("谢谢", { x: 0, y: 5.7, w: W, h: 0.4, fontFace: F_ZH, fontSize: 15, color: C.dim, align: "center" });
})();

pres.writeFile({ fileName: __dirname + "/Next.pptx" }).then((f) => console.log("已生成:", f));
