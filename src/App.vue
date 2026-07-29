<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue";
import snapshots from "./snapshots.json";

const ALL_QUESTIONS = "全部问题";
const tabs = [
  { id: "overview", label: "数据总览", code: "01" },
  { id: "analysis", label: "综合分析", code: "02" },
  { id: "stream", label: "采集流", code: "03" },
];

const query = new URLSearchParams(location.search);
const initialTab = query.get("tab");
const activeTab = ref(tabs.some((tab) => tab.id === initialTab) ? initialTab : "overview");
const stats = ref(null);
const loading = ref(true);
const error = ref("");
const question = ref(query.get("question") || ALL_QUESTIONS);
const device = ref(query.get("device") || "all");
const search = ref("");
const autoRefresh = ref(false);
const lastUpdated = ref("");
const rankMode = ref("media");
const sourceKeywordMode = ref("video");
const selectedBrand = ref("");
const selectedKeyword = ref("");
let timer = null;
let controller = null;

const number = new Intl.NumberFormat("zh-CN");
const fmt = (value) => number.format(Number(value || 0));
const text = (value, fallback = "—") => String(value ?? "").trim() || fallback;
const pct = (value, digits = 1) => `${(Number(value || 0) * 100).toFixed(digits)}%`;
const percentOf = (value, total) => total ? Math.round((Number(value || 0) / total) * 100) : 0;
const shortTime = (value) => {
  const raw = String(value || "").replace("T", " ");
  return raw ? raw.slice(0, 16) : "尚无记录";
};
const shortDate = (value) => String(value || "").slice(5);
const deviceValue = (item) => item?.value || item?.name || item?.instance || item;
const deviceLabel = (item) => {
  if (!item || typeof item !== "object") return item;
  const identity = [item.nickname, item.uid_masked].filter(Boolean).join(" · ");
  return `实例 ${item.instance ?? "—"}${identity ? ` · ${identity}` : ""}`;
};
const deltaText = (value, suffix = "") => {
  const n = Number(value || 0);
  return `${n > 0 ? "+" : ""}${n.toFixed(1)}${suffix}`;
};

const questions = computed(() => stats.value?.questions || []);
const customerName = computed(() => stats.value?.customer?.name || "Doubao");
const devices = computed(() => stats.value?.device_options || []);
const products = computed(() => stats.value?.products || {});
const topBrands = computed(() => (products.value.by_brand || []).slice(0, 8));
const topProducts = computed(() => (products.value.by_product || []).slice(0, 12));
const latestProducts = computed(() =>
  (products.value.latest_products || []).slice().sort(
    (a, b) => Number(a.product_index || 999) - Number(b.product_index || 999)
  )
);
const rankSlotLeaders = computed(() => [1, 2, 3].map((rank) => {
  const rows = (products.value.by_product || [])
    .map((item) => ({ ...item, slotCount: Number(item.rank_counts?.[String(rank)] || 0) }))
    .filter((item) => item.slotCount > 0)
    .sort((a, b) => b.slotCount - a.slotCount || b.count - a.count);
  return { rank, leaders: rows.slice(0, 3) };
}));
const isSingleQuestion = computed(() => question.value !== ALL_QUESTIONS);
const dailySources = computed(() => stats.value?.daily_question_sources?.[0] || null);
const dailyProducts = computed(() => stats.value?.daily_question_products?.[0] || null);
const sourceDates = computed(() => dailySources.value?.dates || []);
const latestSourceDate = computed(() => sourceDates.value.at(-1) || "");
const topDailyLinks = computed(() =>
  dailySources.value?.top_links_by_date?.[latestSourceDate.value] || []
);
const topDailyArticleLinks = computed(() =>
  topDailyLinks.value.filter((item) => item.type === "文章").slice(0, 10)
);
const topDailyVideoLinks = computed(() =>
  topDailyLinks.value.filter((item) => item.type === "视频").slice(0, 10)
);
const latestSourceRefs = computed(() => dailySources.value?.refs_by_date?.at(-1) || 0);
const latestSourceRuns = computed(() => dailySources.value?.runs_by_date?.at(-1) || 0);

const brandAnalytics = computed(() => stats.value?.brand_source_daily_analytics || {});
const brandRows = computed(() => brandAnalytics.value.brands || []);
const activeBrand = computed(() =>
  brandRows.value.find((row) => row.name === selectedBrand.value) || brandRows.value[0] || null
);
const brandPoints = computed(() => activeBrand.value?.points || []);
const latestBrandPoint = computed(() => brandPoints.value.at(-1) || {});
const previousBrandPoint = computed(() => brandPoints.value.at(-2) || {});
const brandDelta = computed(() =>
  (Number(latestBrandPoint.value.rate || 0) - Number(previousBrandPoint.value.rate || 0)) * 100
);

const ownedAnalytics = computed(() => stats.value?.owned_product_source_analytics || {});
const sourceKeywordDays = computed(() =>
  sourceKeywordMode.value === "article"
    ? (ownedAnalytics.value.all_article_keyword_days || [])
    : (ownedAnalytics.value.all_video_keyword_days || [])
);
const sourceKeywordRows = computed(() => {
  const days = sourceKeywordDays.value;
  const latest = days.at(-1) || {};
  const previous = days.at(-2) || {};
  const latestCounts = latest.document_frequency || {};
  const previousCounts = previous.document_frequency || {};
  return Object.entries(latestCounts)
    .map(([keyword, count]) => ({
      keyword,
      count: Number(count || 0),
      coverage: Number(latest.title_count || 0) ? Number(count || 0) / Number(latest.title_count) : 0,
      delta: Number(count || 0) - Number(previousCounts[keyword] || 0),
    }))
    .sort((a, b) => b.count - a.count || b.delta - a.delta || a.keyword.localeCompare(b.keyword, "zh-CN"))
    .slice(0, 20);
});
const baselineProduct = computed(() =>
  (ownedAnalytics.value.products || []).find((row) => row.is_category_baseline) ||
  ownedAnalytics.value.products?.[0] || null
);
const videoKeywords = computed(() => baselineProduct.value?.keywords?.video || []);
const videoKeywordDays = computed(() => baselineProduct.value?.keyword_days?.video || []);
const activeKeyword = computed(() =>
  videoKeywords.value.find((row) => row.keyword === selectedKeyword.value) || videoKeywords.value[0] || null
);
const keywordTrend = computed(() => videoKeywordDays.value.map((day) => {
  const count = Number(day.document_frequency?.[activeKeyword.value?.keyword] || 0);
  const total = Number(day.title_count || 0);
  return { ...day, count, coverage: total ? count / total : 0 };
}));

const rankRows = computed(() => {
  const key = rankMode.value === "domain" ? "by_domain" : rankMode.value === "type" ? "by_type" : "by_media";
  return (stats.value?.[key] || []).slice(0, 12);
});
const rankMax = computed(() => Math.max(1, ...rankRows.value.map((row) => Number(row.count || 0))));
const filteredItems = computed(() => {
  const needle = search.value.trim().toLowerCase();
  const items = stats.value?.latest_items || [];
  if (!needle) return items;
  return items.filter((item) =>
    [item.title, item.domain, item.media, item.question, ...(item.own_products || [])]
      .join(" ").toLowerCase().includes(needle)
  );
});
const freshness = computed(() => {
  if (error.value) return { label: "连接中断", tone: "danger" };
  if (loading.value) return { label: "同步中", tone: "waiting" };
  return { label: "信号在线", tone: "live" };
});
const coverage = computed(() => {
  const c = stats.value?.product_coverage || {};
  return percentOf(c.with_products, c.source_runs);
});
const sourceMix = computed(() => (stats.value?.by_type || []).slice(0, 4));

function linePoints(values, width = 620, height = 180, pad = 14) {
  if (!values.length) return "";
  const span = Math.max(1, values.length - 1);
  return values.map((value, index) => {
    const x = values.length === 1 ? width / 2 : pad + (index / span) * (width - pad * 2);
    const normalized = Math.min(1, Math.max(0, Number(value || 0)));
    const y = height - pad - normalized * (height - pad * 2);
    return `${x.toFixed(1)},${y.toFixed(1)}`;
  }).join(" ");
}
const chartY = (value, height = 180, pad = 14) =>
  height - pad - Math.min(1, Math.max(0, Number(value || 0))) * (height - pad * 2);
const topDayKeywords = (day, limit = 12) =>
  Object.entries(day?.document_frequency || {}).sort((a, b) => b[1] - a[1]).slice(0, limit);

async function refresh({ quiet = false } = {}) {
  if (!quiet) loading.value = true;
  error.value = "";
  try {
    // Pick the hard-coded snapshot matching the currently selected question.
    const key = question.value === ALL_QUESTIONS ? "__all__" : question.value;
    const payload = snapshots[key] || snapshots["__all__"];
    stats.value = payload;
    lastUpdated.value = payload.generated_at || new Date().toLocaleString("zh-CN");
    if (!brandRows.value.some((row) => row.name === selectedBrand.value)) {
      selectedBrand.value = brandRows.value[0]?.name || "";
    }
    if (!videoKeywords.value.some((row) => row.keyword === selectedKeyword.value)) {
      selectedKeyword.value = videoKeywords.value[0]?.keyword || "";
    }
  } catch (cause) {
    error.value = "数据加载失败。";
  } finally {
    loading.value = false;
  }
}

function syncTimer() {
  if (timer) clearInterval(timer);
  timer = autoRefresh.value ? setInterval(() => refresh({ quiet: true }), 5000) : null;
}
function selectTab(id) {
  activeTab.value = id;
  window.scrollTo({ top: 0, behavior: "smooth" });
}
function chooseQuestion(value, tab = activeTab.value) {
  question.value = value;
  activeTab.value = tab;
}
function syncFilters() {
  const params = new URLSearchParams();
  if (question.value !== ALL_QUESTIONS) params.set("question", question.value);
  if (device.value !== "all") params.set("device", device.value);
  history.replaceState(null, "", params.size ? `?${params}` : location.pathname);
  refresh();
}

watch(autoRefresh, syncTimer);
watch([question, device], syncFilters);
onMounted(() => { refresh(); syncTimer(); });
onBeforeUnmount(() => {
  if (timer) clearInterval(timer);
  if (controller) controller.abort();
});
</script>

<template>
  <div class="shell">
    <header class="topbar">
      <a class="brand" href="./" aria-label="豆包 Signal Desk 首页">
        <span class="brand-mark"><i></i><i></i><i></i></span>
        <span><b>{{ customerName.toUpperCase() }}</b><em>SIGNAL DESK / 2.1</em></span>
      </a>
      <nav class="main-nav" aria-label="主导航">
        <button v-for="tab in tabs" :key="tab.id" :class="{ active: activeTab === tab.id }" @click="selectTab(tab.id)">
          <small>{{ tab.code }}</small>{{ tab.label }}
        </button>
      </nav>
      <div class="live-cluster">
        <span class="signal" :class="freshness.tone"><i></i>{{ freshness.label }}</span>
        <button class="icon-button" title="立即刷新" :disabled="loading" @click="refresh()">
          <svg viewBox="0 0 24 24"><path d="M20 11a8 8 0 1 0-2.34 5.66M20 4v7h-7"/></svg>
        </button>
      </div>
    </header>

    <section class="control-rail">
      <div class="filter-block question-filter">
        <label for="question">观察问题</label>
        <select id="question" v-model="question">
          <option :value="ALL_QUESTIONS">全部问题</option>
          <option v-for="item in questions" :key="item.question" :value="item.question">{{ item.question }}</option>
        </select>
      </div>
      <div class="filter-block">
        <label for="device">采集设备</label>
        <select id="device" v-model="device">
          <option value="all">全部设备</option>
          <option v-for="item in devices" :key="deviceValue(item)" :value="deviceValue(item)">
            {{ item.label || deviceLabel(item) }}
          </option>
        </select>
      </div>
      <label class="auto-switch" :class="{ active: autoRefresh }">
        <input v-model="autoRefresh" type="checkbox">
        <span class="switch-track"><i></i></span>
        <span class="switch-copy"><b>{{ autoRefresh ? "自动刷新已开启" : "自动刷新已关闭" }}</b><small>每 5 秒同步一次</small></span>
      </label>
      <div class="stamp"><span>LAST SYNC</span><b>{{ shortTime(lastUpdated) }}</b></div>
    </section>

    <main>
      <div v-if="error" class="error-banner"><b>数据连接异常</b><span>{{ error }}</span><button @click="refresh()">重新连接</button></div>

      <template v-if="activeTab === 'overview'">
        <section class="hero">
          <div class="hero-copy">
            <p class="eyebrow"><span>LIVE INTELLIGENCE</span> / 实时舆情观测</p>
            <h1>豆包数据，<br><span>实时看清。</span></h1>
            <p class="hero-note">回答、信源、品牌和标题趋势。</p>
          </div>
          <div class="hero-orbit">
            <div class="orbit orbit-one"></div><div class="orbit orbit-two"></div>
            <div class="orbit-core"><b>{{ fmt(stats?.today_runs) }}</b><span>今日运行</span></div>
            <span class="orbit-tag tag-a">REFS {{ fmt(stats?.total_refs) }}</span>
            <span class="orbit-tag tag-b">RUN #{{ fmt(stats?.latest_run_no) }}</span>
          </div>
        </section>

        <section class="metric-strip">
          <article><span>01 / 累计运行</span><b>{{ fmt(stats?.total_runs) }}</b><small>{{ fmt(stats?.question_count) }} 个问题样本</small></article>
          <article><span>02 / 引用总量</span><b>{{ fmt(stats?.total_refs) }}</b><small>{{ fmt(stats?.unique_links) }} 条独立链接</small></article>
          <article><span>03 / 品牌提及</span><b>{{ fmt(products.total_mentions) }}</b><small>{{ fmt(products.unique_brands) }} 个品牌</small></article>
          <article class="accent-metric"><span>04 / 今日采集</span><b>{{ fmt(stats?.today_runs) }}</b><small>{{ fmt(stats?.latest_refs) }} 条最新引用</small></article>
        </section>

        <section class="overview-audit">
          <article class="audit-card"><span>回答完整率</span><b>{{ percentOf(stats?.latest_count, stats?.latest_expected_count) }}%</b><p>{{ fmt(stats?.latest_count) }} / {{ fmt(stats?.latest_expected_count) }} 个期望信源</p></article>
          <article class="audit-card"><span>品牌识别覆盖</span><b>{{ coverage }}%</b><p>{{ fmt(stats?.product_coverage?.with_products) }} / {{ fmt(stats?.product_coverage?.source_runs) }} 轮已识别</p></article>
          <article class="audit-card"><span>设备与账号</span><b>{{ fmt(stats?.device_overview?.length || devices.length) }}</b><p>{{ fmt(stats?.account_count) }} 个账号 · {{ device === "all" ? "全部设备" : device }}</p></article>
          <article class="audit-card warning"><span>待处理异常</span><b>{{ fmt(stats?.capture_skips?.active_count) }}</b><p>采集跳过或正文归档失败会在对应口径中剔除</p></article>
        </section>

        <section class="dashboard-grid">
          <article class="panel wide">
            <header class="panel-head"><div><span>QUESTION PULSE</span><h2>问题热度与采集进度</h2></div><button @click="selectTab('stream')">查看采集流 →</button></header>
            <div class="question-list">
              <button v-for="(item, index) in questions.slice(0, 10)" :key="item.question" class="question-row" @click="chooseQuestion(item.question, 'analysis')">
                <span class="rank">{{ String(index + 1).padStart(2, '0') }}</span>
                <span class="question-name"><b>{{ item.question }}</b><small>最近 {{ shortTime(item.latest_run_time) }}</small></span>
                <span class="micro-track"><i :style="{ width: `${percentOf(item.refs, questions[0]?.refs)}%` }"></i></span>
                <strong>{{ fmt(item.refs) }}<small>引用</small></strong>
              </button>
              <div v-if="!questions.length" class="empty">采集开始后，问题脉冲会出现在这里。</div>
            </div>
          </article>
          <article class="panel dark-panel">
            <header class="panel-head"><div><span>QUALITY CHECK</span><h2>数据健康度</h2></div></header>
            <div class="quality-score">
              <div class="score-ring" :style="{ '--score': `${coverage * 3.6}deg` }"><b>{{ coverage }}%</b><span>品牌覆盖</span></div>
              <div class="quality-copy">
                <p><span>来源运行</span><b>{{ fmt(stats?.product_coverage?.source_runs) }}</b></p>
                <p><span>识别品牌</span><b>{{ fmt(stats?.product_coverage?.with_products) }}</b></p>
                <p><span>待处理异常</span><b>{{ fmt(stats?.capture_skips?.active_count) }}</b></p>
              </div>
            </div>
            <div class="health-note" :class="{ warning: stats?.capture_skips?.active_count }"><i></i>{{ stats?.capture_skips?.active_count ? "发现待处理采集异常。" : "当前没有未处理采集异常。" }}</div>
          </article>
          <article class="panel source-mix">
            <header class="panel-head"><div><span>SOURCE MIX</span><h2>内容形态</h2></div></header>
            <div class="donut-wrap">
              <div class="donut" :style="{ '--video': `${percentOf(sourceMix[0]?.count, stats?.total_refs) * 3.6}deg` }"><span><b>{{ fmt(stats?.total_refs) }}</b>全部引用</span></div>
              <div class="legend"><p v-for="(row, index) in sourceMix" :key="row.name"><i :class="`color-${index}`"></i><span>{{ row.name }}</span><b>{{ percentOf(row.count, stats?.total_refs) }}%</b></p></div>
            </div>
          </article>
          <article class="panel latest-signal">
            <header class="panel-head"><div><span>LATEST SIGNAL</span><h2>最新一条引用</h2></div><span class="run-chip">RUN {{ text(filteredItems[0]?.run_no) }}</span></header>
            <template v-if="filteredItems[0]">
              <p class="latest-kind">{{ filteredItems[0].source_type }} · {{ filteredItems[0].media }}</p>
              <a :href="filteredItems[0].href" target="_blank">{{ filteredItems[0].title }}</a>
              <footer><span>{{ filteredItems[0].question }}</span><b>{{ filteredItems[0].domain }}</b></footer>
            </template>
          </article>
        </section>
      </template>

      <template v-else-if="activeTab === 'analysis'">
        <section v-if="!isSingleQuestion" class="select-question-panel">
          <span>SELECT ONE QUESTION</span><h2>请选择一个问题，查看不混淆的每日信源统计</h2>
          <div><button v-for="item in questions" :key="item.question" @click="chooseQuestion(item.question, 'analysis')">{{ item.question }}<b>{{ fmt(item.refs) }} 引用</b></button></div>
        </section>
        <template v-if="isSingleQuestion">
          <!-- 信源日报 -->
          <section class="page-intro"><p class="eyebrow"><span>DAILY SOURCE</span> / 信源日报</p><h1>每日信源</h1><p>引用排行、来源变化和标题关键词。</p></section>
          <section class="daily-kpis">
            <article><span>观察日期</span><b>{{ latestSourceDate || "—" }}</b></article>
            <article><span>当日引用</span><b>{{ fmt(latestSourceRefs) }}</b></article>
            <article><span>当日运行</span><b>{{ fmt(latestSourceRuns) }}</b></article>
            <article><span>文章 / 视频前十</span><b>{{ fmt(topDailyArticleLinks.length) }} / {{ fmt(topDailyVideoLinks.length) }}</b></article>
          </section>
          <section class="source-top-grid">
            <article class="panel source-top-panel">
              <header class="panel-head"><div><span>ARTICLE TOP 10</span><h2>文章信源链接前十名</h2></div><b>{{ latestSourceDate }}</b></header>
              <div class="source-link-list">
                <a v-for="(item, index) in topDailyArticleLinks" :key="item.href" :href="item.href" target="_blank" rel="noreferrer">
                  <span>{{ String(index + 1).padStart(2, "0") }}</span><i>文章</i>
                  <b>{{ item.title }}</b><strong>{{ fmt(item.count) }} 次</strong><em>↗</em>
                </a>
                <div v-if="!topDailyArticleLinks.length" class="empty">当日尚无可展示的文章信源。</div>
              </div>
            </article>
            <article class="panel source-top-panel">
              <header class="panel-head"><div><span>VIDEO TOP 10</span><h2>视频信源链接前十名</h2></div><b>{{ latestSourceDate }}</b></header>
              <div class="source-link-list">
                <a v-for="(item, index) in topDailyVideoLinks" :key="item.href" :href="item.href" target="_blank" rel="noreferrer">
                  <span>{{ String(index + 1).padStart(2, "0") }}</span><i class="video">视频</i>
                  <b>{{ item.title }}</b><strong>{{ fmt(item.count) }} 次</strong><em>↗</em>
                </a>
                <div v-if="!topDailyVideoLinks.length" class="empty">当日尚无可展示的视频信源。</div>
              </div>
            </article>
          </section>
          <section class="analytics-grid source-ranking-grid">
            <article class="panel">
              <header class="panel-head"><div><span>SOURCE RANKING</span><h2>累计信源排行</h2></div></header>
              <div class="segmented"><button :class="{ active: rankMode === 'media' }" @click="rankMode='media'">媒体</button><button :class="{ active: rankMode === 'domain' }" @click="rankMode='domain'">域名</button><button :class="{ active: rankMode === 'type' }" @click="rankMode='type'">类型</button></div>
              <div class="compact-ranking"><p v-for="(row,index) in rankRows.slice(0,8)" :key="row.name"><span>{{ index+1 }}</span><b>{{ row.name }}</b><i><em :style="{width:`${percentOf(row.count,rankMax)}%`}"></em></i><strong>{{ fmt(row.count) }}</strong></p></div>
            </article>
          </section>
          <article class="panel matrix-panel">
            <header class="panel-head"><div><span>DAILY MATRIX</span><h2>每日来源变化</h2></div><small>变化值为相邻日期引用次数差</small></header>
            <div class="matrix-wrap"><table><thead><tr><th>来源</th><th v-for="date in sourceDates" :key="date">{{ shortDate(date) }}</th><th>累计</th><th>变化</th></tr></thead>
              <tbody><tr v-for="row in dailySources?.media_rows || []" :key="row.name"><th>{{ row.name }}</th><td v-for="(count,i) in row.counts" :key="i">{{ fmt(count) }}</td><td><b>{{ fmt(row.total) }}</b></td><td :class="{up:row.delta>0,down:row.delta<0}">{{ row.delta>0?"+":"" }}{{ fmt(row.delta) }}</td></tr></tbody>
            </table></div>
          </article>
          <article class="panel matrix-panel source-keyword-panel">
            <header class="panel-head">
              <div><span>DAILY SOURCE KEYWORDS</span><h2>每日信源关键词变化</h2></div>
              <div class="segmented">
                <button :class="{active:sourceKeywordMode==='video'}" @click="sourceKeywordMode='video'">视频标题</button>
                <button :class="{active:sourceKeywordMode==='article'}" @click="sourceKeywordMode='article'">文章标题</button>
              </div>
            </header>
            <div v-if="sourceKeywordRows.length" class="keyword-change-grid">
              <div v-for="row in sourceKeywordRows" :key="row.keyword">
                <b>{{ row.keyword }}</b><span>{{ fmt(row.count) }} 次</span><em>{{ pct(row.coverage,0) }}</em>
                <strong :class="{up:row.delta>0,down:row.delta<0}">{{ sourceKeywordDays.length < 2 ? "首日" : `${row.delta>0?"+":""}${row.delta}` }}</strong>
              </div>
            </div>
            <div v-else class="empty">{{ sourceKeywordMode === "article" ? "当前没有文章标题样本。" : "当前没有视频标题样本。" }}</div>
            <div v-if="sourceKeywordDays.length" class="keyword-day-list source-days">
              <div v-for="day in sourceKeywordDays" :key="day.date">
                <b>{{ day.date }}</b><span>{{ fmt(day.title_count) }} 个标题</span>
                <p><em v-for="[key,count] in topDayKeywords(day)" :key="key">{{ key }} <strong>{{ count }}</strong></em></p>
              </div>
            </div>
          </article>

          <!-- 品牌趋势 -->
          <section class="page-intro brand-intro"><p class="eyebrow"><span>BRAND TREND</span> / 品牌趋势</p><h1>品牌提及趋势</h1><p>回答、视频标题和文章内容分开统计。</p></section>
          <template v-if="activeBrand">
            <section class="brand-selector"><span>选择品牌</span><button v-for="row in brandRows" :key="row.name" :class="{active:activeBrand?.name===row.name}" @click="selectedBrand=row.name">{{ row.name }}</button></section>
            <section class="daily-kpis brand-kpis">
              <article><span>回答正文提及率</span><b>{{ pct(latestBrandPoint.rate) }}</b><small>{{ fmt(latestBrandPoint.mentioned_runs) }} / {{ fmt(latestBrandPoint.denominator_runs) }} 轮</small></article>
              <article><span>较前日变化</span><b :class="{up:brandDelta>0,down:brandDelta<0}">{{ deltaText(brandDelta,"pp") }}</b><small>百分点变化</small></article>
              <article><span>视频标题提及率</span><b>{{ pct(latestBrandPoint.title_video_within_titled_share) }}</b><small>{{ fmt(latestBrandPoint.source_title_refs) }} 次标题命中</small></article>
              <article><span>文章有效样本提及率</span><b>{{ pct(latestBrandPoint.source_article_within_eligible_share) }}</b><small>{{ fmt(latestBrandPoint.source_article_refs) }} / {{ fmt(latestBrandPoint.article_eligible_refs) }} 篇</small></article>
            </section>
            <section class="analytics-grid">
              <article class="panel span-2 trend-panel">
                <header class="panel-head"><div><span>MENTION RATE</span><h2>{{ activeBrand.name }} 每日提及率</h2></div><div class="trend-legend"><span class="answer">回答正文</span><span class="video">视频标题</span><span class="article">文章标题+正文</span></div></header>
                <svg class="trend-chart" viewBox="0 0 620 180" preserveAspectRatio="none">
                  <path d="M14 14V166H606" class="axis"/>
                  <polyline :points="linePoints(brandPoints.map(p=>p.rate))" class="answer-line"/>
                  <polyline :points="linePoints(brandPoints.map(p=>p.title_video_within_titled_share))" class="video-line"/>
                  <polyline :points="linePoints(brandPoints.map(p=>p.source_article_within_eligible_share))" class="article-line"/>
                  <circle v-if="brandPoints.length===1" cx="310" :cy="chartY(brandPoints[0].rate)" r="5" class="answer-dot"/>
                  <circle v-if="brandPoints.length===1" cx="310" :cy="chartY(brandPoints[0].title_video_within_titled_share)" r="4" class="video-dot"/>
                  <circle v-if="brandPoints.length===1" cx="310" :cy="chartY(brandPoints[0].source_article_within_eligible_share)" r="3" class="article-dot"/>
                </svg>
                <div class="chart-dates"><span v-for="point in brandPoints" :key="point.date">{{ shortDate(point.date) }}</span></div>
              </article>
              <article class="panel quality-panel">
                <header class="panel-head"><div><span>DENOMINATOR AUDIT</span><h2>最新日有效样本</h2></div></header>
                <p><span>回答正文轮次</span><b>{{ fmt(latestBrandPoint.denominator_runs) }}</b></p>
                <p><span>有标题的视频</span><b>{{ fmt(brandAnalytics.days?.at(-1)?.video_title_available_refs) }}</b></p>
                <p><span>文章有效样本</span><b>{{ fmt(latestBrandPoint.article_eligible_refs) }}</b></p>
                <p><span>文章正文成功</span><b>{{ fmt(brandAnalytics.days?.at(-1)?.article_content_available_refs) }}</b></p>
                <p><span>文章正文失败跳过</span><b>{{ fmt(brandAnalytics.days?.at(-1)?.article_content_failed_refs) }}</b></p>
                <small>正文抓取失败的文章不会被当作“品牌未提及”；但标题已明确命中品牌的文章仍计入命中样本。</small>
              </article>
            </section>
            <article class="panel matrix-panel">
              <header class="panel-head"><div><span>BRAND DAILY TABLE</span><h2>全部品牌每日正文提及率</h2></div></header>
              <div class="matrix-wrap"><table><thead><tr><th>品牌</th><th v-for="date in dailyProducts?.dates || []" :key="date">{{ shortDate(date) }}</th><th>最新排名</th><th>变化</th></tr></thead>
                <tbody><tr v-for="row in dailyProducts?.brand_rows || []" :key="row.name"><th>{{ row.name }}</th><td v-for="(count,i) in row.counts" :key="i">{{ fmt(count) }}/{{ fmt(dailyProducts.runs_by_date[i]) }}<small>{{ ((count/(dailyProducts.runs_by_date[i]||1))*100).toFixed(1) }}%</small></td><td>#{{ row.latest_rank }}</td><td :class="{up:row.delta>0,down:row.delta<0}">{{ row.delta>0?"+":"" }}{{ row.delta }}</td></tr></tbody>
              </table></div>
            </article>
            <article class="panel examples-panel">
              <header class="panel-head"><div><span>SOURCE EVIDENCE</span><h2>{{ activeBrand.name }} 信源证据</h2></div></header>
              <div class="source-link-list compact"><a v-for="(item,index) in activeBrand.source_examples || []" :key="item.href" :href="item.href" target="_blank"><span>{{ index+1 }}</span><i :class="{video:item.source_type==='视频'}">{{ item.source_type }}</i><b>{{ item.title }}</b><strong>{{ fmt(item.refs) }} 次</strong><em>↗</em></a><div v-if="!activeBrand.source_examples?.length" class="empty">暂无信源证据。</div></div>
            </article>
          </template>
          <div v-else class="empty large">该问题还没有可用的品牌趋势数据。</div>

          <!-- 标题洞察 -->
          <section class="page-intro keyword-intro"><p class="eyebrow"><span>TITLE INTELLIGENCE</span> / 标题洞察</p><h1>标题关键词</h1><p>视频、文章分开查看。</p></section>
          <template v-if="baselineProduct">
            <div class="title-quality-note">
              <b>标题完整性</b>
              <span>已用页面正文补全 {{ fmt(ownedAnalytics.quality?.title_enriched_rows) }} 条标题</span>
              <span :class="{ warning: ownedAnalytics.quality?.suspected_truncated_rows }">仍疑似截断 {{ fmt(ownedAnalytics.quality?.suspected_truncated_rows) }} 条</span>
            </div>
            <section class="keyword-selector"><span>视频标题关键词</span><button v-for="row in videoKeywords.slice(0,18)" :key="row.keyword" :class="{active:activeKeyword?.keyword===row.keyword}" @click="selectedKeyword=row.keyword">{{ row.keyword }} <b>{{ pct(row.coverage,0) }}</b></button></section>
            <section class="analytics-grid">
              <article class="panel span-2 trend-panel">
                <header class="panel-head"><div><span>DAILY KEYWORD</span><h2>“{{ activeKeyword?.keyword || "—" }}”每日标题覆盖率</h2></div><b>{{ activeKeyword ? pct(activeKeyword.coverage) : "—" }}</b></header>
                <svg class="trend-chart" viewBox="0 0 620 180" preserveAspectRatio="none"><path d="M14 14V166H606" class="axis"/><polyline :points="linePoints(keywordTrend.map(p=>p.coverage))" class="keyword-line"/><circle v-if="keywordTrend.length===1" cx="310" :cy="chartY(keywordTrend[0].coverage)" r="5" class="answer-dot"/></svg>
                <div class="chart-dates"><span v-for="point in keywordTrend" :key="point.date">{{ shortDate(point.date) }} · {{ fmt(point.count) }}/{{ fmt(point.title_count) }}</span></div>
              </article>
              <article class="panel keyword-rank">
                <header class="panel-head"><div><span>TODAY'S WORDS</span><h2>视频标题关键词</h2></div></header>
                <p v-for="(row,index) in videoKeywords.slice(0,10)" :key="row.keyword"><span>{{ index+1 }}</span><b>{{ row.keyword }}</b><i><em :style="{width:`${percentOf(row.coverage,videoKeywords[0]?.coverage)}%`}"></em></i><strong>{{ pct(row.coverage,0) }}</strong></p>
              </article>
            </section>
            <section class="analytics-grid">
              <article class="panel">
                <header class="panel-head"><div><span>ARTICLE THEMES</span><h2>文章标题/正文主题</h2></div></header>
                <div class="theme-list"><p v-for="row in baselineProduct.themes?.slice(0,10) || []" :key="row.name"><b>{{ row.name }}</b><span>文章 {{ pct(row.article_rate) }}</span><span>视频 {{ pct(row.video_rate) }}</span><strong :class="{up:row.video_minus_article>0,down:row.video_minus_article<0}">{{ deltaText(Number(row.video_minus_article||0)*100,"pp") }}</strong></p></div>
              </article>
              <article class="panel">
                <header class="panel-head"><div><span>ARTICLE KEYWORDS</span><h2>文章关键词</h2></div></header>
                <div class="tag-cloud"><span v-for="row in baselineProduct.keywords?.article?.slice(0,24) || []" :key="row.keyword">{{ row.keyword }} <b>{{ pct(row.coverage,0) }}</b></span><div v-if="!baselineProduct.keywords?.article?.length" class="empty">文章正文暂无有效归档，未生成文章关键词。</div></div>
              </article>
            </section>
            <article class="panel matrix-panel">
              <header class="panel-head"><div><span>KEYWORD DAY LOG</span><h2>每日视频标题关键词变化</h2></div><small>按每日标题文档频次排序</small></header>
              <div class="keyword-day-list"><div v-for="day in videoKeywordDays" :key="day.date"><b>{{ day.date }}</b><span>{{ fmt(day.title_count) }} 个标题 / {{ fmt(day.source_refs) }} 个视频信源</span><p><em v-for="[key,count] in topDayKeywords(day)" :key="key">{{ key }} <strong>{{ count }}</strong></em></p></div><div v-if="!videoKeywordDays.length" class="empty">至少积累一个观察日后显示。</div></div>
            </article>
          </template>
          <div v-else class="empty large">该问题还没有标题关键词分析数据。</div>

          <!-- 产品雷达 -->
          <section class="page-intro product-intro"><p class="eyebrow"><span>PRODUCT RADAR</span> / 产品雷达</p><h1>品牌与产品</h1><p>提及率、排名和每日变化。</p></section>
          <section class="recommendation-ranks">
            <article class="panel latest-recommendations">
              <header class="panel-head"><div><span>LATEST ANSWER ORDER</span><h2>最新正文推荐名次</h2></div><b>RUN {{ products.latest_product_run_no || "—" }}</b></header>
              <div v-if="latestProducts.length" class="latest-rank-list">
                <div v-for="item in latestProducts" :key="`${item.run_no}-${item.product_index}-${item.product_name}`">
                  <span>第 {{ item.product_index }} 名</span><b>{{ item.product_name || item.brand_name || "未识别名称" }}</b><small>{{ item.brand_name }}</small>
                </div>
              </div>
              <div v-else class="empty">最新回答正文尚未提取出产品名次。</div>
            </article>
            <article class="panel slot-leaders">
              <header class="panel-head"><div><span>RANK SLOT WINNERS</span><h2>各名次高频产品</h2></div></header>
              <div v-for="slot in rankSlotLeaders" :key="slot.rank" class="slot-row">
                <span>第 {{ slot.rank }} 名</span>
                <p><b v-for="item in slot.leaders" :key="item.name">{{ item.name }} <em>{{ fmt(item.slotCount) }} 次</em></b><small v-if="!slot.leaders.length">暂无数据</small></p>
              </div>
            </article>
          </section>
          <section class="product-grid">
            <article class="panel brand-board"><header class="panel-head"><div><span>BRAND SHARE</span><h2>品牌声量</h2></div><b>{{ fmt(products.unique_brands) }} BRANDS</b></header><div class="brand-cloud"><div v-for="(brand,index) in topBrands" :key="brand.name" :class="`brand-tile tile-${index}`"><span>{{ String(index+1).padStart(2,"0") }}</span><b>{{ brand.name }}</b><strong>{{ fmt(brand.count) }}</strong></div><div v-if="!topBrands.length" class="empty">完成产品识别后显示品牌声量。</div></div></article>
            <article class="panel product-table"><header class="panel-head"><div><span>PRODUCT LEADERBOARD</span><h2>产品排行</h2></div></header><div class="table-head"><span>#</span><span>产品</span><span>提及</span></div><div v-for="(item,index) in topProducts" :key="item.name" class="table-row"><span>{{ String(index+1).padStart(2,"0") }}</span><b>{{ item.name }}</b><strong>{{ fmt(item.count) }}</strong></div></article>
          </section>
          <article v-if="dailyProducts" class="panel matrix-panel"><header class="panel-head"><div><span>PRODUCT DAILY MATRIX</span><h2>产品每日提及率与排名</h2></div></header><div class="matrix-wrap"><table><thead><tr><th>产品</th><th v-for="date in dailyProducts.dates" :key="date">{{ shortDate(date) }}</th><th>最新排名</th><th>变化</th></tr></thead><tbody><tr v-for="row in dailyProducts.product_rows" :key="row.name"><th>{{ row.name }}</th><td v-for="(count,i) in row.counts" :key="i">{{ fmt(count) }}/{{ fmt(dailyProducts.runs_by_date[i]) }}<small>{{ ((count/(dailyProducts.runs_by_date[i]||1))*100).toFixed(1) }}%</small></td><td>#{{ row.latest_rank }}</td><td :class="{up:row.delta>0,down:row.delta<0}">{{ row.delta>0?"+":"" }}{{ row.delta }}</td></tr></tbody></table></div></article>
        </template>
      </template>

      <template v-else>
        <section class="page-intro stream-intro"><p class="eyebrow"><span>CAPTURE STREAM</span> / 采集流</p><h1>最新采集</h1><p>按标题、媒体、域名或产品检索。</p></section>
        <section class="stream-tools"><div class="search-box"><svg viewBox="0 0 24 24"><circle cx="11" cy="11" r="7"/><path d="m20 20-4-4"/></svg><input v-model="search" type="search" placeholder="搜索标题、媒体、域名或产品…"><kbd>{{ filteredItems.length }} 条</kbd></div><a class="lab-link" href="/rag-lab" target="_blank">打开 RAG / ML 实验室 →</a></section>
        <section class="stream-list"><article v-for="item in filteredItems" :key="`${item.run_no}-${item.index}-${item.href}`" class="stream-item"><div class="stream-index"><span>{{ String(item.index || "—").padStart(2,"0") }}</span><small>RUN {{ item.run_no }}</small></div><div class="stream-main"><p><span>{{ item.source_type }}</span>{{ item.media }} · {{ item.domain }}</p><a :href="item.href" target="_blank">{{ item.title }}</a><footer><span>{{ item.question }}</span><b v-for="own in item.own_products || []" :key="own">{{ own }}</b></footer></div><a class="arrow-link" :href="item.href" target="_blank">↗</a></article><div v-if="!filteredItems.length" class="empty large">没有匹配的采集记录。</div></section>
      </template>
    </main>

    <footer class="site-footer"><span>DOUBAO SIGNAL DESK</span><p>本地实时数据 · 北京时间 · {{ fmt(stats?.account_count) }} 个账号</p><b>V2.1 / {{ new Date().getFullYear() }}</b></footer>
  </div>
</template>
