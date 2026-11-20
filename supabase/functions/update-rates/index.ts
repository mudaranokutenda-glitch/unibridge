// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";

// Called every hour by the database (cron job "update-exchange-rates").
//
// 1. OFFICIAL rate ("bank"): live from ExchangeRate-API
//    (https://www.exchangerate-api.com). The key is the Edge Function secret
//    EXCHANGERATE_API_KEY. It is never in the app or in GitHub.
//
// 2. PARALLEL rate ("black_market"): the Algiers rate (Square Port-Saïd),
//    the one everyone uses. No official API exists, so this "bot" reads
//    several public sources and only saves a rate when they AGREE:
//      - EXDZ API (api.exchangedz.com), if the secret EXDZ_API_KEY is set
//      - public rate tables (babalweb, eurodz, sarfdz)
//    Rules (so a wrong number never reaches the students):
//      - each value must be between 1.3x and 2.6x the official rate
//      - 2 or more sources must agree within 2 %  -> saved (their median)
//      - only 1 source: saved only if it is within 3 % of the last saved rate
//      - otherwise: nothing is saved, the app keeps the last rate and shows
//        its age. There is NO estimate any more.
//    If the Attaché / admin typed a rate in the app (Staff hub > Parallel
//    rates) less than parallel_manual_hours ago, the bot leaves it alone.
//
// Test without saving anything: send {"dry_run": true}. The full report is
// in the function's Logs either way.

const PAIRS = ["USD/DZD", "EUR/DZD"] as const;
type Pair = (typeof PAIRS)[number];
const AUTO_LOCATION = "Square Port-Saïd";
// Locations used by rates typed in the app by staff (set_parallel_rate).
// Old rows from the previous system ("Alger", "official") are NOT staff rates.
const STAFF_LOCATIONS = ["Alger (staff)", "Annaba"];
const USER_AGENT = "UniBridgeRatesBot/1.0 (student exchange app, 1 visit per hour)";

type Quote = { buy: number | null; sell: number };
type SourceReport = { source: string; quotes: Partial<Record<Pair, Quote>>; note?: string };

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function round2(v: number) {
  return Math.round(v * 100) / 100;
}

function median(values: number[]) {
  const s = [...values].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}

async function fetchText(url: string, timeoutMs = 12000) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(url, {
      headers: { "User-Agent": USER_AGENT, "Accept-Language": "fr,en;q=0.8" },
      signal: ctrl.signal,
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return await res.text();
  } finally {
    clearTimeout(t);
  }
}

// HTML page -> plain text on one line (tables become "Euro 274.00 276.00 ...").
function htmlToText(html: string) {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;|&#160;/gi, " ")
    .replace(/&eacute;/gi, "é")
    .replace(/&amp;/gi, "&")
    .replace(/&#8364;|&euro;/gi, "€")
    .replace(/\s+/g, " ");
}

const NUMBER = /(?<!\d)(\d{2,3}(?:[.,]\d{1,2})?)(?!\d)/g;

// Finds the label (e.g. "1 Euro") and reads the numbers just after it.
// "buy_sell": two numbers (the lower one = buy). "sell_only": one number.
function readQuote(text: string, label: RegExp, mode: "buy_sell" | "sell_only"): Quote | null {
  const re = new RegExp(label.source, "g");
  let m: RegExpExecArray | null;
  while ((m = re.exec(text)) !== null) {
    const after = text.slice(m.index + m[0].length, m.index + m[0].length + 120);
    const nums = [...after.matchAll(NUMBER)]
      .map((x) => Number(x[1].replace(",", ".")))
      .filter((v) => v >= 100 && v <= 800);
    if (mode === "sell_only" && nums.length >= 1) return { buy: null, sell: nums[0] };
    if (mode === "buy_sell" && nums.length >= 2) {
      const lo = Math.min(nums[0], nums[1]);
      const hi = Math.max(nums[0], nums[1]);
      // buy and sell are always close (a few DA apart)
      if ((hi - lo) / hi <= 0.05) return { buy: lo, sell: hi };
    }
  }
  return null;
}

// ---- The public pages the bot reads ----
const PAGES: {
  source: string;
  url: string;
  mode: "buy_sell" | "sell_only";
  labels: Record<Pair, RegExp>;
  staleIf?: RegExp;
}[] = [
  {
    source: "babalweb",
    url: "https://www.babalweb.com/finance/taux-de-change/marche-noir/",
    mode: "buy_sell",
    labels: { "EUR/DZD": /1\s*Euro\b/, "USD/DZD": /1\s*Dollar\s+am[ée]ricain/ },
  },
  {
    source: "eurodz",
    url: "https://eurodz.com/en/",
    mode: "buy_sell",
    labels: { "EUR/DZD": /Euro\s*\(EUR\)/, "USD/DZD": /Dollar\s+US\s*\(USD\)/ },
    // The site writes this when its own update failed: then we ignore it.
    staleIf: /more than \d+\s*h old/i,
  },
  {
    source: "sarfdz",
    url: "https://sarfdz.com/currencies",
    mode: "sell_only",
    labels: { "EUR/DZD": /Euro\b/, "USD/DZD": /Dollar\s+US\b/ },
  },
];

async function readPage(p: (typeof PAGES)[number]): Promise<SourceReport> {
  try {
    const text = htmlToText(await fetchText(p.url));
    if (p.staleIf && p.staleIf.test(text)) {
      return { source: p.source, quotes: {}, note: "site says its rates are old" };
    }
    const quotes: Partial<Record<Pair, Quote>> = {};
    for (const pair of PAIRS) {
      const q = readQuote(text, p.labels[pair], p.mode);
      if (q) quotes[pair] = q;
    }
    return { source: p.source, quotes, note: Object.keys(quotes).length ? undefined : "no rate found on the page" };
  } catch (e) {
    return { source: p.source, quotes: {}, note: `could not read: ${String(e).slice(0, 80)}` };
  }
}

// EXDZ API (only if you got a key: secret EXDZ_API_KEY).
async function readExdz(): Promise<SourceReport | null> {
  const key = Deno.env.get("EXDZ_API_KEY");
  if (!key) return null;
  const quotes: Partial<Record<Pair, Quote>> = {};
  const notes: string[] = [];
  for (const pair of PAIRS) {
    const cur = pair.split("/")[0];
    try {
      const res = await fetch(
        `https://api.exchangedz.com/v1/rates/latest?currency=${cur}&source=parallel`,
        { headers: { Authorization: `Bearer ${key}`, "User-Agent": USER_AGENT } },
      );
      if (!res.ok) {
        notes.push(`${cur}: HTTP ${res.status}`);
        continue;
      }
      const body = await res.json();
      const row = (body?.data ?? [])[0];
      const buy = Number(row?.buy);
      const sell = Number(row?.sell);
      const updated = Date.parse(row?.updatedAt ?? "");
      const ageHours = Number.isFinite(updated) ? (Date.now() - updated) / 3600000 : 0;
      if (ageHours > 72) {
        notes.push(`${cur}: older than 3 days`);
        continue;
      }
      if (sell > 0) quotes[pair] = { buy: buy > 0 ? Math.min(buy, sell) : null, sell: Math.max(buy || 0, sell) };
    } catch (e) {
      notes.push(`${cur}: ${String(e).slice(0, 60)}`);
    }
  }
  return { source: "exdz-api", quotes, note: notes.length ? notes.join("; ") : undefined };
}

// Decides the rate for one pair from all sources (or null = keep the last one).
function decide(
  pair: Pair,
  sources: SourceReport[],
  official: number,
  last: { buy: number; sell: number } | null,
) {
  const all = sources
    .map((s) => ({ source: s.source, q: s.quotes[pair] }))
    .filter((x) => x.q) as { source: string; q: Quote }[];
  const sane = all.filter((x) => x.q.sell >= official * 1.3 && x.q.sell <= official * 2.6);
  const rejected = all.filter((x) => !sane.includes(x)).map((x) => x.source);
  if (sane.length === 0) {
    return { rate: null, why: "no usable source", rejected };
  }
  const mid = median(sane.map((x) => x.q.sell));
  const agree = sane.filter((x) => Math.abs(x.q.sell - mid) / mid <= 0.02);
  const sell = round2(median(agree.map((x) => x.q.sell)));
  const buys = agree.map((x) => x.q.buy).filter((b): b is number => b !== null);
  if (buys.length === 0) {
    return { rate: null, why: "no source gave a buy rate", rejected };
  }
  const buy = round2(Math.min(median(buys), sell));
  const used = agree.map((x) => x.source);

  if (agree.length >= 2) return { rate: { buy, sell }, why: `${agree.length} sources agree`, used, rejected };
  if (last && Math.abs(sell - last.sell) / last.sell <= 0.03) {
    return { rate: { buy, sell }, why: "1 source, close to the last rate", used, rejected };
  }
  return { rate: null, why: "only 1 source and it moved too much: kept the last rate", used, rejected };
}

Deno.serve(async (req) => {
  // Only the database (which knows the secret) may call this.
  const secret = Deno.env.get("CRON_SECRET");
  if (!secret || req.headers.get("x-cron-secret") !== secret) {
    return json({ error: "Not allowed" }, 401);
  }

  let dryRun = false;
  try {
    dryRun = (await req.json())?.dry_run === true;
  } catch (_) {
    // no body: a normal hourly run
  }

  const apiKey = Deno.env.get("EXCHANGERATE_API_KEY");
  if (!apiKey) return json({ error: "Secret EXCHANGERATE_API_KEY not set" }, 500);

  try {
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // ---- 1. Official rates (one call: base USD) ----
    const res = await fetch(`https://v6.exchangerate-api.com/v6/${apiKey}/latest/USD`);
    const data = await res.json();
    if (!res.ok || data.result !== "success") {
      // Never print the key: only the API's error type.
      return json({ error: "ExchangeRate-API failed", type: data["error-type"] ?? res.status }, 502);
    }
    const cr = data.conversion_rates ?? {};
    const usdDzd = Number(cr.DZD);
    const eurPerUsd = Number(cr.EUR);
    if (!(usdDzd > 0) || !(eurPerUsd > 0)) {
      return json({ error: "DZD or EUR missing in the API answer" }, 502);
    }
    const official: Record<Pair, number> = {
      "USD/DZD": usdDzd,
      "EUR/DZD": usdDzd / eurPerUsd,
    };

    const { data: settingRows } = await admin
      .from("app_settings")
      .select("key, value")
      .in("key", ["parallel_manual_hours"]);
    const manualHours = Number(settingRows?.[0]?.value) > 0 ? Number(settingRows[0].value) : 24;

    // ---- 2. Parallel: read all sources at the same time ----
    const [exdz, ...pages] = await Promise.all([readExdz(), ...PAGES.map(readPage)]);
    const sources = [exdz, ...pages].filter(Boolean) as SourceReport[];

    const report: Record<string, unknown> = { dry_run: dryRun, sources };
    const inserts: Record<string, unknown>[] = [];

    for (const pair of PAIRS) {
      const mid = round2(official[pair]);
      inserts.push({ pair, source: "bank", buy_rate: mid, sell_rate: mid, location: "official" });
      const pairReport: Record<string, unknown> = { official: mid };
      report[pair] = pairReport;

      // A rate typed by staff recently wins over the bot.
      const since = new Date(Date.now() - manualHours * 3600 * 1000).toISOString();
      const { data: manual } = await admin
        .from("exchange_rates")
        .select("id")
        .eq("pair", pair)
        .eq("source", "black_market")
        .in("location", STAFF_LOCATIONS)
        .gte("updated_at", since)
        .limit(1);
      if (manual && manual.length > 0) {
        pairReport.parallel = "kept the rate typed by staff";
        continue;
      }

      const { data: lastRows } = await admin
        .from("exchange_rates")
        .select("id, buy_rate, sell_rate, location")
        .eq("pair", pair)
        .eq("source", "black_market")
        .neq("location", "estimate")
        .order("updated_at", { ascending: false })
        .limit(1);
      const lastRow = lastRows?.[0];
      const last = lastRow
        ? { buy: Number(lastRow.buy_rate), sell: Number(lastRow.sell_rate) }
        : null;

      const d = decide(pair, sources, official[pair], last);
      Object.assign(pairReport, d);
      if (!d.rate || dryRun) continue;

      if (
        lastRow && lastRow.location === AUTO_LOCATION &&
        last!.buy === d.rate.buy && last!.sell === d.rate.sell
      ) {
        // Same rate as before: only mark it as checked now (updated_at).
        await admin.from("exchange_rates")
          .update({ buy_rate: d.rate.buy })
          .eq("id", lastRow.id);
        pairReport.saved = "unchanged (checked now)";
      } else {
        inserts.push({
          pair,
          source: "black_market",
          buy_rate: d.rate.buy,
          sell_rate: d.rate.sell,
          location: AUTO_LOCATION,
        });
        pairReport.saved = "new rate";
      }
    }

    console.log(JSON.stringify(report));
    if (dryRun) return json({ ok: true, report });

    const { error: insertError } = await admin.from("exchange_rates").insert(inserts);
    if (insertError) return json({ error: insertError.message }, 500);

    // Keep the table small. Old estimates are removed too.
    const old = new Date(Date.now() - 30 * 24 * 3600 * 1000).toISOString();
    await admin.from("exchange_rates").delete().lt("updated_at", old);
    await admin.from("exchange_rates").delete().eq("location", "estimate");

    return json({ ok: true, report });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
