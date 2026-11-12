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
function validDate(value: unknown) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(value + "T00:00:00Z");
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
}
async function createMember(body: Record<string, unknown>) {
  const name = String(body.display_name ?? "").trim();
  const password = String(body.password ?? "");
  const confirm = String(body.confirm_password ?? "");
  const type = String(body.account_type ?? "writer");
  const gender = String(body.gender ?? "");
  const birthDate = body.birth_date;
  const allowedTypes = ["writer","director","actor","presenter","voice","producer"];
  if (name.length < 2 || name.length > 120) return reply(400,{error:"اكتب اسمًا صحيحًا."});
  if (password.length < 8 || password.length > 128 || password !== confirm) return reply(400,{error:"تأكد من تطابق الرقم السري وأن يكون 8 أحرف على الأقل."});
  if (!allowedTypes.includes(type)) return reply(400,{error:"اختر مجال العضوية."});
  if (!["male","female"].includes(gender) || !validDate(birthDate)) return reply(400,{error:"أكمل النوع وتاريخ الميلاد."});

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
    user_metadata:{display_name:name,account_type:type}
  });
  if (createError || !created.user) return reply(400,{error:"تعذر إنشاء العضوية. حاول مرة أخرى."});
  const userId = created.user.id;
  let imageUrl: string | null = null;
  try {
    const {error:directoryError} = await admin.from("member_login_directory").insert({member_number:memberNumber,user_id:userId});
    if (directoryError) throw directoryError;
    const imageData = typeof body.avatar_data_url === "string" ? body.avatar_data_url : "";
    if (imageData) {
      const match = imageData.match(/^data:(image\/(?:jpeg|png|webp));base64,([A-Za-z0-9+/=]+)$/);
      if (!match) throw new Error("صيغة الصورة غير مدعومة.");
      const mime = match[1];
      const bytes = Uint8Array.from(atob(match[2]), c => c.charCodeAt(0));
      if (!bytes.length || bytes.length > 3145728) throw new Error("حجم الصورة يجب ألا يتجاوز 3 ميجابايت.");
      const ext = mime === "image/jpeg" ? "jpg" : mime === "image/png" ? "png" : "webp";
      const path = `${userId}/avatar.${ext}`;
      const {error:uploadError} = await admin.storage.from("member-avatars").upload(path,bytes,{contentType:mime,upsert:true});
      if (uploadError) throw uploadError;
      imageUrl = admin.storage.from("member-avatars").getPublicUrl(path).data.publicUrl;
    }
    const {error:profileError} = await admin.from("member_profiles").insert({
      user_id:userId,display_name:name,account_type:type,gender,birth_date:birthDate,
      member_number:memberNumber,image_url:imageUrl,profile_status:"pending"
    });
    if (profileError) throw profileError;
    const {data:sessionData,error:loginError} = await publicAuth.auth.signInWithPassword({email,password});
    if (loginError || !sessionData.session) throw loginError || new Error("تعذر بدء الجلسة.");
    return reply(200,{member_number:memberNumber,session:sessionData.session,user:sessionData.user});
  } catch (error) {
    await admin.auth.admin.deleteUser(userId);
    return reply(400,{error:error instanceof Error ? error.message : "تعذر إكمال إنشاء العضوية."});
  }
}
async function signInMember(body: Record<string, unknown>) {
  const memberNumber = String(body.member_number ?? "").trim();
  const password = String(body.password ?? "");
  if (!/^\d{8}$/.test(memberNumber) || !password) return reply(400,{error:"أدخل رقم العضوية والرقم السري."});
  const {data:record,error} = await admin.from("member_login_directory").select("user_id").eq("member_number",memberNumber).maybeSingle();
  if (error || !record) return reply(401,{error:"رقم العضوية أو الرقم السري غير صحيح."});
  const {data:userData,error:userError} = await admin.auth.admin.getUserById(record.user_id);
  if (userError || !userData.user?.email) return reply(401,{error:"رقم العضوية أو الرقم السري غير صحيح."});
  const {data,error:loginError} = await publicAuth.auth.signInWithPassword({email:userData.user.email,password});
  if (loginError || !data.session) return reply(401,{error:"رقم العضوية أو الرقم السري غير صحيح."});
  return reply(200,{session:data.session,user:data.user});
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok",{headers:corsHeaders});
  if (req.method !== "POST") return reply(405,{error:"طريقة الطلب غير مدعومة."});
  try {
    const body = await req.json();
    if (body.action === "signup") return await createMember(body);
    if (body.action === "login") return await signInMember(body);
    return reply(400,{error:"طلب غير معروف."});
  } catch {
    return reply(400,{error:"تعذر قراءة الطلب."});
  }
});
