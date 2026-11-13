import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const url = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
const publicAuth = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });

function reply(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}
function internalEmail(memberNumber: string) {
  return `m${memberNumber}@members.scenario-w-scenarist.invalid`;
}
function randomMemberNumber() {
  const bytes = new Uint32Array(1);
  crypto.getRandomValues(bytes);
  return String(10000000 + (bytes[0] % 90000000));
}

async function hashRateLimitKey(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, "0")).join("");
}
async function consumeOneRateLimit(ip: string, action: "signup" | "login", identity: string, limit: number, windowSeconds: number) {
  const keyHash = await hashRateLimitKey(ip + ":" + action + ":" + identity);
  const {data,error} = await admin.rpc("consume_member_auth_attempt", {
    p_key_hash:keyHash,p_action:action,p_limit:limit,p_window_seconds:windowSeconds
  });
  if (error) throw new Error("خدمة التحقق مشغولة مؤقتًا. حاول لاحقًا.");
  return data === true;
}
async function consumeRateLimit(req: Request, action: "signup" | "login", body: Record<string, unknown>) {
  const ip = req.headers.get("cf-connecting-ip")
    || req.headers.get("x-real-ip")
    || req.headers.get("x-forwarded-for")?.split(",")[0]?.trim()
    || "unknown";
  if (action === "signup") return await consumeOneRateLimit(ip,action,"signup",5,3600);
  const memberNumber = String(body.member_number ?? "").trim();
  const ipAllowed = await consumeOneRateLimit(ip,action,"all-members",30,900);
  if (!ipAllowed) return false;
  return await consumeOneRateLimit(ip,action,memberNumber,8,900);
}
async function createMember(body: Record<string, unknown>) {
  const name = String(body.display_name ?? "").trim();
  const password = String(body.password ?? "");
  const confirm = String(body.confirm_password ?? "");
  const age = Number(body.age);
  const country = String(body.country ?? "").trim();
  if (name.length < 2 || name.length > 120) return reply(400,{error:"اكتب اسمًا صحيحًا."});
  if (password.length < 8 || password.length > 128 || password !== confirm) return reply(400,{error:"تأكد من تطابق الرقم السري وأن يكون 8 أحرف على الأقل."});
  if (!Number.isInteger(age) || age < 1 || age > 120) return reply(400,{error:"أدخل عمرًا صحيحًا."});
  if (country.length < 2 || country.length > 100) return reply(400,{error:"اكتب اسم البلد بشكل صحيح."});

  let memberNumber = "";
  for (let i=0;i<8;i++) {
    const candidate = randomMemberNumber();
    const {data} = await admin.from("member_login_directory").select("member_number").eq("member_number",candidate).maybeSingle();
    if (!data) { memberNumber = candidate; break; }
  }
  if (!memberNumber) return reply(503,{error:"تعذر إنشاء رقم العضوية الآن. حاول مرة أخرى."});

  const email = internalEmail(memberNumber);
  const {data:created,error:createError} = await admin.auth.admin.createUser({
    email, password, email_confirm:true,
    user_metadata:{display_name:name},
    app_metadata:{member_number:memberNumber}
  });
  if (createError || !created.user) return reply(400,{error:"تعذر إنشاء العضوية. حاول مرة أخرى."});
  const userId = created.user.id;
  let imageUrl: string | null = null;
  let uploadedAvatarPath: string | null = null;
  try {
    const {error:directoryError} = await admin.from("member_login_directory").insert({member_number:memberNumber,user_id:userId});
    if (directoryError) throw directoryError;
    const imageData = typeof body.avatar_data_url === "string" ? body.avatar_data_url : "";
    if (imageData) {
      if (imageData.length > 4200000) throw new Error("حجم الصورة أكبر من المسموح.");
      const match = imageData.match(/^data:(image\/(?:jpeg|png|webp));base64,([A-Za-z0-9+/=]+)$/);
      if (!match) throw new Error("صيغة الصورة غير مدعومة.");
      const mime = match[1];
      const bytes = Uint8Array.from(atob(match[2]), c => c.charCodeAt(0));
      if (!bytes.length || bytes.length > 3145728) throw new Error("حجم الصورة يجب ألا يتجاوز 3 ميجابايت.");
      const ext = mime === "image/jpeg" ? "jpg" : mime === "image/png" ? "png" : "webp";
      const path = `${userId}/avatar.${ext}`;
      uploadedAvatarPath = path;
      const {error:uploadError} = await admin.storage.from("member-avatars").upload(path,bytes,{contentType:mime,upsert:true});
      if (uploadError) throw uploadError;
      imageUrl = admin.storage.from("member-avatars").getPublicUrl(path).data.publicUrl;
    }
    const {error:privateDetailsError} = await admin.from("member_private_details").insert({
      user_id:userId,age,country
    });
    if (privateDetailsError) throw privateDetailsError;
    const {data:sessionData,error:loginError} = await publicAuth.auth.signInWithPassword({email,password});
    if (loginError || !sessionData.session) throw loginError || new Error("تعذر بدء الجلسة.");
    return reply(200,{member_number:memberNumber,session:sessionData.session,user:sessionData.user});
  } catch (error) {
    if (uploadedAvatarPath) await admin.storage.from("member-avatars").remove([uploadedAvatarPath]);
    await admin.auth.admin.deleteUser(userId);
    return reply(400,{error:error instanceof Error ? error.message : "تعذر إكمال إنشاء العضوية."});
  }
}
async function signInMember(body: Record<string, unknown>) {
  const memberNumber = String(body.member_number ?? "").trim();
  const password = String(body.password ?? "");
  if (!/^\d{8}$/.test(memberNumber) || !password) return reply(400,{error:"أدخل رقم العضوية والرقم السري."});
  const {data:record,error} = await admin.from("member_login_directory").select("user_id").eq("member_number",memberNumber).maybeSingle();
  if (error) throw new Error("تعذر التحقق من رقم العضوية مؤقتًا.");
  if (!record) {
    // Pass unknown member numbers through Auth as well, so repeated guesses still hit Auth rate limits.
    await publicAuth.auth.signInWithPassword({
      email: "unknown-member@members.scenario-w-scenarist.invalid",
      password
    });
    return reply(401,{error:"رقم العضوية أو الرقم السري غير صحيح."});
  }
  const {data:userData,error:userError} = await admin.auth.admin.getUserById(record.user_id);
  if (userError) throw new Error("تعذر التحقق من حساب العضوية مؤقتًا.");
  if (!userData.user?.email) return reply(401,{error:"رقم العضوية أو الرقم السري غير صحيح."});
  const {data,error:loginError} = await publicAuth.auth.signInWithPassword({email:userData.user.email,password});
  if (loginError || !data.session) return reply(401,{error:"رقم العضوية أو الرقم السري غير صحيح."});
  return reply(200,{session:data.session,user:data.user});
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok",{headers:corsHeaders});
  if (req.method !== "POST") return reply(405,{error:"طريقة الطلب غير مدعومة."});
  const suppliedKey = req.headers.get("apikey") || "";
  const allowedKeys = [
    Deno.env.get("SUPABASE_ANON_KEY"),
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY")
  ].filter((value): value is string => Boolean(value));
  if (!allowedKeys.includes(suppliedKey)) return reply(401,{error:"طلب غير مصرح به."});
  let rawBody: string;
  try {
    rawBody = await req.text();
  } catch {
    return reply(400,{error:"تعذر قراءة بيانات الطلب."});
  }
  if (new TextEncoder().encode(rawBody).byteLength > 5000000) return reply(413,{error:"حجم الطلب أكبر من المسموح."});

  let body: Record<string, unknown>;
  try {
    const parsed: unknown = JSON.parse(rawBody);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return reply(400,{error:"بيانات الطلب غير صحيحة."});
    body = parsed as Record<string, unknown>;
  } catch {
    return reply(400,{error:"صيغة بيانات الطلب غير صحيحة."});
  }

  if (body.action !== "signup" && body.action !== "login") return reply(400,{error:"طلب غير معروف."});
  const action = body.action as "signup" | "login";

  try {
    if (!await consumeRateLimit(req,action,body)) {
      return reply(429,{error:"وصلت للحد المسموح من المحاولات. انتظر قليلًا ثم حاول مرة أخرى."});
    }
  } catch (error) {
    console.error("member-auth rate-limit service unavailable", error instanceof Error ? error.name : "unknown");
    return reply(503,{error:"خدمة التحقق من المحاولات غير متاحة مؤقتًا. حاول بعد قليل."});
  }

  try {
    if (action === "signup") return await createMember(body);
    return await signInMember(body);
  } catch (error) {
    console.error("member-auth operation failed", action, error instanceof Error ? error.name : "unknown");
    return reply(503,{error:"تعذر إتمام العملية مؤقتًا. حاول بعد قليل."});
  }
});
