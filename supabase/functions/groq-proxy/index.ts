import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const DAILY_LIMIT = 100;
const GROQ_URL = "https://api.groq.com/openai/v1/chat/completions";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonError(405, "Method not allowed");
  }

  // 1. Validate auth
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return jsonError(401, "Missing auth token");
  }
  const jwt = authHeader.replace("Bearer ", "");

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userError } = await supabase.auth.getUser(jwt);
  if (userError || !userData.user) {
    return jsonError(401, "Invalid auth token");
  }
  const userId = userData.user.id;

  // 2. Check and increment quota
  const today = new Date().toISOString().split("T")[0];
  const { data: usageRow } = await supabase
    .from("ai_usage")
    .select("requests")
    .eq("user_id", userId)
    .eq("date", today)
    .maybeSingle();

  const currentCount = usageRow?.requests ?? 0;
  if (currentCount >= DAILY_LIMIT) {
    return jsonError(429, `Daily limit of ${DAILY_LIMIT} requests reached.`);
  }

  await supabase
    .from("ai_usage")
    .upsert(
      { user_id: userId, date: today, requests: currentCount + 1 },
      { onConflict: "user_id,date" }
    );

  // 3. Parse body, forward to Groq
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return jsonError(400, "Invalid JSON body");
  }

  const groqKey = Deno.env.get("GROQ_API_KEY");
  if (!groqKey) {
    return jsonError(500, "Server missing Groq key");
  }

  const isStream = body.stream === true;

  const groqResponse = await fetch(GROQ_URL, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${groqKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  if (!groqResponse.ok) {
    const errText = await groqResponse.text();
    return jsonError(groqResponse.status, `Groq error: ${errText}`);
  }

  // 4. Return response (streaming or JSON)
  if (isStream) {
    return new Response(groqResponse.body, {
      status: 200,
      headers: {
        ...corsHeaders,
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        "Connection": "keep-alive",
      },
    });
  } else {
    const data = await groqResponse.json();
    return new Response(JSON.stringify(data), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

function jsonError(status: number, message: string): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
