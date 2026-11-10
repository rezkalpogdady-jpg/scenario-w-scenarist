import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const FEEDS = [
  { url: "https://news.google.com/rss/search?q=%28%D8%B3%D9%8A%D9%86%D9%85%D8%A7+OR+%D9%81%D9%8A%D9%84%D9%85+OR+%D9%85%D9%87%D8%B1%D8%AC%D8%A7%D9%86+%D8%B3%D9%8A%D9%86%D9%85%D8%A7%D8%A6%D9%8A%29&hl=ar&gl=EG&ceid=EG:ar", category: "سينما وفعاليات" },
  { url: "https://news.google.com/rss/search?q=%28%D8%AF%D8%B1%D8%A7%D9%85%D8%A7+OR+%D9%85%D8%B3%D9%84%D8%B3%D9%84+OR+%D9%85%D9%85%D8%AB%D9%84+OR+%D9%85%D8%AE%D8%B1%D8%AC%29&hl=ar&gl=EG&ceid=EG:ar", category: "دراما وفنانون" }
];

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Cache-Control": "public, max-age=600, s-maxage=600"
};

function decodeXml(value: string): string {
  return value.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .replace(/<[^>]*>/g, " ")
    .replace(/&amp;/g, "&").replace(/&quot;/g, '"').replace(/&apos;|&#39;/g, "'")
    .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/&#x([\da-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)))
    .replace(/\s+/g, " ").trim();
}

function tagValue(block: string, names: string[]): string {
  for (const name of names) {
    const match = block.match(new RegExp("<" + name + "(?:\\s[^>]*)?>([\\s\\S]*?)<\\/" + name + "\\s*>", "i"));
    if (match) return decodeXml(match[1]);
  }
  return "";
}

function parseFeed(xml: string, category: string) {
  const blocks = xml.match(/<(?:item|entry)(?:\s[^>]*)?>[\s\S]*?<\/(?:item|entry)\s*>/gi) || [];
  return blocks.map((block) => {
    const title = tagValue(block, ["title"]);
    const linkMatch = block.match(/<link\b[^>]*href=["']([^"']+)["'][^>]*\/?\s*>/i);
    const link = linkMatch ? decodeXml(linkMatch[1]) : tagValue(block, ["link"]);
    const description = tagValue(block, ["description", "summary", "content:encoded", "content"]);
    const source = tagValue(block, ["source"]);
    const published = tagValue(block, ["pubDate", "published", "updated"]);
    let host = "";
    try { host = new URL(link).hostname.replace(/^www\./, ""); } catch { /* invalid link */ }
    return { title, description: description.slice(0, 240), url: link, source: source || host || "مصدر الخبر", category, published_at: published };
  }).filter((item) => item.title && /^https:\/\//i.test(item.url));
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "GET") return new Response(JSON.stringify({ error: "Method not allowed" }), {
    status: 405, headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" }
  });
  const results = await Promise.allSettled(FEEDS.map(async (feed) => {
    const response = await fetch(feed.url, {
      headers: { "User-Agent": "ScenarioWaScenarist/6.8.53", "Accept": "application/rss+xml, application/xml, text/xml" },
      signal: AbortSignal.timeout(9000)
    });
    if (!response.ok) throw new Error("Feed returned " + response.status);
    return parseFeed(await response.text(), feed.category);
  }));
  const items = results.flatMap((result) => result.status === "fulfilled" ? result.value : []);
  const unique = new Map<string, typeof items[number]>();
  for (const item of items) if (!unique.has(item.url)) unique.set(item.url, item);
  const news = [...unique.values()].sort((a, b) => (Date.parse(b.published_at || "") || 0) - (Date.parse(a.published_at || "") || 0)).slice(0, 12);
  return new Response(JSON.stringify({ items: news, updated_at: new Date().toISOString() }), {
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" }
  });
});
