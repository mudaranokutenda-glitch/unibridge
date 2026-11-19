// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";

// Called every hour by the database (cron job "update-exchange-rates").
//
// 1. OFFICIAL rate ("bank"): live from ExchangeRate-API
//    (https://www.exchangerate-api.com, free plan: 1 500 calls a month,
//    one call an hour = about 720). The key is the Edge Function secret
//    EXCHANGERATE_API_KEY. It is never in the app or in GitHub.
//
// 2. PARALLEL rate ("black_market"): no public API exists for the Algerian
//    square market. The rate a staff member typed in the app (Staff hub >
//    Parallel rates) is kept while it is recent (app_settings
//    parallel_manual_hours, default 24). After that, an ESTIMATE is written:
//    official rate x parallel_premium (app_settings, set by the admin),
//    buy/sell = estimate -/+ parallel_spread / 2. Estimated rows have
//    location = 'estimate' and the app says so.

const PAIRS = ["USD/DZD", "EUR/DZD"];

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function round2(v: number) {
  return Math.round(v * 100) / 100;
}

Deno.serve(async (req) => {
  // Only the database (which knows the secret) may call this.
  const secret = Deno.env.get("CRON_SECRET");
  if (!secret || req.headers.get("x-cron-secret") !== secret) {
    return json({ error: "Not allowed" }, 401);
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
    const official: Record<string, number> = {
      "USD/DZD": usdDzd,
      "EUR/DZD": usdDzd / eurPerUsd,
    };

    // ---- Settings (app_settings, changed by the admin in SQL) ----
    const { data: settingRows } = await admin
      .from("app_settings")
      .select("key, value")
      .in("key", ["parallel_premium", "parallel_spread", "parallel_manual_hours"]);
    const setting = (k: string, d: number) => {
      const row = (settingRows ?? []).find((r) => r.key === k);
      const v = Number(row?.value);
      return Number.isFinite(v) && v > 0 ? v : d;
    };
    const premium = setting("parallel_premium", 0); // 0 = no estimate
    const spread = setting("parallel_spread", 2);
    const manualHours = setting("parallel_manual_hours", 24);

    const rows: Record<string, unknown>[] = [];
    const report: Record<string, unknown> = {};

    for (const pair of PAIRS) {
      const mid = round2(official[pair]);
      rows.push({ pair, source: "bank", buy_rate: mid, sell_rate: mid, location: "official" });
      report[pair] = { official: mid };

      if (premium <= 0) continue;

      // ---- 2. Parallel: keep a recent rate typed by staff ----
      const since = new Date(Date.now() - manualHours * 3600 * 1000).toISOString();
      const { data: manual } = await admin
        .from("exchange_rates")
        .select("id")
        .eq("pair", pair)
        .eq("source", "black_market")
        .neq("location", "estimate")
        .gte("updated_at", since)
        .limit(1);
      if (manual && manual.length > 0) {
        report[pair] = { ...report[pair] as object, parallel: "kept (typed by staff)" };
        continue;
      }
      const estimate = official[pair] * premium;
      rows.push({
        pair,
        source: "black_market",
        buy_rate: round2(estimate - spread / 2),
        sell_rate: round2(estimate + spread / 2),
        location: "estimate",
      });
      report[pair] = { ...report[pair] as object, parallel_estimate: round2(estimate) };
    }

    const { error: insertError } = await admin.from("exchange_rates").insert(rows);
    if (insertError) return json({ error: insertError.message }, 500);

    // Keep the table small: rows older than 30 days are not shown anyway.
    const old = new Date(Date.now() - 30 * 24 * 3600 * 1000).toISOString();
    await admin.from("exchange_rates").delete().lt("updated_at", old);

    return json({ ok: true, report });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
