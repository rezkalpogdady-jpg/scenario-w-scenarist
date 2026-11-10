import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405, headers: corsHeaders });

  try {
    const { scenario_id } = await req.json();
    const id = String(scenario_id || "");
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)) {
      return new Response(JSON.stringify({ error: "Invalid scenario id" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

    const { data: row, error } = await admin
      .from("scenario_scripts")
      .select("storage_path,rights_holder,rights_status,rights_confirmed")
      .eq("id", id)
      .eq("published", true)
      .eq("rights_confirmed", true)
      .single();

    if (error || !row?.storage_path || !row.rights_confirmed ||
        row.rights_status === "unverified" || !String(row.rights_holder || "").trim()) {
      return new Response(JSON.stringify({ error: "Scenario is not available for public reading" }), { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // Temporary URL is used by the in-page canvas reader; no direct public Storage policy is granted.
    const { data: signed, error: signError } = await admin.storage
      .from("scenario-scripts")
      .createSignedUrl(row.storage_path, 900);

    if (signError || !signed?.signedUrl) {
      return new Response(JSON.stringify({ error: "Unable to prepare reader" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    return new Response(JSON.stringify({ signedUrl: signed.signedUrl }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" },
    });
  } catch {
    return new Response(JSON.stringify({ error: "Invalid request" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
