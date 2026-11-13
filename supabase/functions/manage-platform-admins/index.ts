import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const OWNER_ID = "0ecade12-50a9-4b30-ba90-4fab3393c7b3";

Deno.serve(async (req: Request) => {
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "يجب تسجيل الدخول أولاً." }, 401);
  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const userClient = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } } });
  const adminClient = createClient(url, serviceKey);

  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) return json({ error: "جلسة الدخول غير صالحة." }, 401);
  if (userData.user.id !== OWNER_ID) return json({ error: "إدارة صلاحيات المديرين متاحة لصاحب المنصة فقط." }, 403);

  const { data: ownerMembership, error: ownerMembershipError } = await adminClient
    .from("admin_users").select("user_id").eq("user_id", OWNER_ID).maybeSingle();
  if (ownerMembershipError || !ownerMembership) return json({ error: "تعذر التحقق من صلاحية مالك المنصة." }, 403);

  let body: { action?: string; member_number?: string; user_id?: string };
  try { body = await req.json(); } catch { return json({ error: "بيانات الطلب غير صحيحة." }, 400); }

  if (body.action === "list") {
    const directory: any[] = [];
    for (let offset = 0; offset < 100000; offset += 1000) {
      const { data, error } = await adminClient.from("member_login_directory")
        .select("member_number,user_id,created_at").order("created_at", { ascending: false })
        .range(offset, offset + 999);
      if (error) return json({ error: "تعذر تحميل قائمة الأعضاء." }, 500);
      directory.push(...(data || []));
      if (!data || data.length < 1000) break;
    }

    const userIds = directory.map(row => row.user_id);
    const profiles = new Map<string, string>();
    for (let offset = 0; offset < userIds.length; offset += 500) {
      const chunk = userIds.slice(offset, offset + 500);
      if (!chunk.length) continue;
      const { data, error } = await adminClient.from("member_profiles")
        .select("user_id,display_name").in("user_id", chunk);
      if (error) return json({ error: "تعذر تحميل أسماء الأعضاء." }, 500);
      for (const profile of data || []) profiles.set(profile.user_id, profile.display_name || "");
    }

    const authUsers = new Map<string, any>();
    const wanted = new Set(userIds);
    for (let page = 1; page <= 1000 && wanted.size > authUsers.size; page++) {
      const { data, error } = await adminClient.auth.admin.listUsers({ page, perPage: 1000 });
      if (error) return json({ error: "تعذر قراءة بيانات حسابات الأعضاء." }, 500);
      for (const user of data.users || []) {
        if (wanted.has(user.id)) authUsers.set(user.id, user);
      }
      if (!data.users || data.users.length < 1000) break;
    }

    const { data: admins, error: adminsError } = await adminClient.from("admin_users").select("user_id");
    if (adminsError) return json({ error: "تعذر قراءة صلاحيات المديرين." }, 500);
    const adminIds = new Set((admins || []).map(row => row.user_id));
    const members = directory.map(row => {
      const authUser = authUsers.get(row.user_id);
      return {
        user_id: row.user_id,
        member_number: row.member_number,
        display_name: profiles.get(row.user_id) || authUser?.user_metadata?.display_name || "عضو بدون اسم",
        created_at: row.created_at,
        is_admin: adminIds.has(row.user_id),
        is_owner: row.user_id === OWNER_ID,
      };
    });
    return json({ members });
  }

  if (body.action === "add") {
    const memberNumber = String(body.member_number || "").trim();
    if (!/^\d{8}$/.test(memberNumber)) return json({ error: "رقم العضوية يجب أن يتكون من 8 أرقام." }, 400);
    const { data: directoryRow, error: directoryError } = await adminClient
      .from("member_login_directory").select("user_id").eq("member_number", memberNumber).maybeSingle();
    if (directoryError) return json({ error: "تعذر البحث عن العضو." }, 500);
    if (!directoryRow) return json({ error: "لم يتم العثور على عضو بهذا الرقم." }, 404);
    const targetId = directoryRow.user_id;
    if (targetId === OWNER_ID) return json({ error: "هذا الحساب هو مالك المنصة بالفعل." }, 400);
    const { data: targetData, error: targetError } = await adminClient.auth.admin.getUserById(targetId);
    if (targetError || !targetData.user) return json({ error: "تعذر العثور على حساب العضو." }, 404);
    const { error: insertError } = await adminClient.from("admin_users")
      .upsert({ user_id: targetId }, { onConflict: "user_id" });
    if (insertError) return json({ error: "تعذرت إضافة العضو إلى قائمة المديرين." }, 500);
    const { error: updateError } = await adminClient.auth.admin.updateUserById(targetId, {
      app_metadata: { ...(targetData.user.app_metadata || {}), role: "admin" },
    });
    if (updateError) {
      await adminClient.from("admin_users").delete().eq("user_id", targetId);
      return json({ error: "تعذر منح صلاحية المدير؛ تم التراجع عن الإضافة." }, 500);
    }
    return json({ success: true, message: "تمت ترقية العضو إلى مدير بنجاح." });
  }

  if (body.action === "remove") {
    const targetId = String(body.user_id || "").trim();
    if (!targetId) return json({ error: "حدد حساب المدير." }, 400);
    if (targetId === OWNER_ID) return json({ error: "لا يمكن إزالة صلاحيات مالك المنصة." }, 403);
    const { data: targetData, error: targetError } = await adminClient.auth.admin.getUserById(targetId);
    if (targetError || !targetData.user) return json({ error: "لم يتم العثور على حساب المدير." }, 404);
    const { error: deleteError } = await adminClient.from("admin_users").delete().eq("user_id", targetId);
    if (deleteError) return json({ error: "تعذر إزالة صلاحية المدير." }, 500);
    const { error: updateError } = await adminClient.auth.admin.updateUserById(targetId, {
      app_metadata: { ...(targetData.user.app_metadata || {}), role: "member" },
    });
    if (updateError) {
      await adminClient.from("admin_users").upsert({ user_id: targetId }, { onConflict: "user_id" });
      return json({ error: "تعذر تحديث دور الحساب؛ تمت استعادة عضويته كمدير." }, 500);
    }
    return json({ success: true, message: "تم إلغاء صلاحية المدير." });
  }

  return json({ error: "الإجراء غير معروف." }, 400);
});
