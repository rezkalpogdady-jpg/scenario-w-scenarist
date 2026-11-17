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

  let body: { action?: string; member_number?: string; user_id?: string; query?: string };
  try { body = await req.json(); } catch { return json({ error: "بيانات الطلب غير صحيحة." }, 400); }

  if (body.action === "list") {
    const { data: admins, error: adminsError } = await adminClient.from("admin_users").select("user_id");
    if (adminsError) return json({ error: "تعذر قراءة صلاحيات المديرين." }, 500);
    const adminIds = [...new Set((admins || []).map((row: any) => row.user_id))];
    if (!adminIds.length) return json({ members: [] });
    const [{ data: directory, error: directoryError }, { data: profileRows, error: profileError }] = await Promise.all([
      adminClient.from("member_login_directory").select("member_number,user_id").in("user_id", adminIds),
      adminClient.from("member_profiles").select("user_id,display_name").in("user_id", adminIds),
    ]);
    if (directoryError || profileError) return json({ error: "تعذر تحميل بيانات المديرين." }, 500);
    const profiles = new Map<string, string>((profileRows || []).map((row: any) => [row.user_id, row.display_name || ""]));
    const numbers = new Map<string, string>((directory || []).map((row: any) => [row.user_id, row.member_number]));
    return json({ members: adminIds.map((userId: string) => ({
      user_id: userId, member_number: numbers.get(userId) || "",
      display_name: profiles.get(userId) || "مدير بدون اسم",
      is_admin: true, is_owner: userId === OWNER_ID,
    })) });
  }

  if (body.action === "search") {
    const rawQuery = String(body.query || "").trim();
    if (rawQuery.length < 2 || rawQuery.length > 120) return json({ error: "اكتب حرفين على الأقل للبحث." }, 400);
    const safeQuery = rawQuery.replace(/[%_(),.*\\]/g, " ").replace(/\s+/g, " ").trim();
    const found = new Map<string, { user_id: string; member_number: string; display_name: string }>();
    if (/^\d{2,8}$/.test(rawQuery)) {
      const { data: numberRows, error: numberError } = await adminClient.from("member_login_directory")
        .select("user_id,member_number").like("member_number", rawQuery + "%").limit(20);
      if (numberError) return json({ error: "تعذر البحث برقم العضوية." }, 500);
      for (const row of numberRows || []) found.set(row.user_id, { user_id: row.user_id, member_number: row.member_number, display_name: "" });
    }
    if (safeQuery.length >= 2) {
      const { data: profileRows, error: profileError } = await adminClient.from("member_profiles")
        .select("user_id,display_name").ilike("display_name", "%" + safeQuery + "%").limit(20);
      if (profileError) return json({ error: "تعذر البحث باسم العضو." }, 500);
      const profileIds = (profileRows || []).map((row: any) => row.user_id);
      const profileNames = new Map<string, string>((profileRows || []).map((row: any) => [row.user_id, row.display_name || ""]));
      if (profileIds.length) {
        const { data: directoryRows, error: directoryError } = await adminClient.from("member_login_directory")
          .select("user_id,member_number").in("user_id", profileIds);
        if (directoryError) return json({ error: "تعذر تحميل أرقام عضويات نتائج البحث." }, 500);
        for (const row of directoryRows || []) found.set(row.user_id, {
          user_id: row.user_id, member_number: row.member_number,
          display_name: profileNames.get(row.user_id) || "",
        });
      }
    }
    const userIds = [...found.keys()];
    if (!userIds.length) return json({ members: [] });
    const { data: adminRows, error: adminRowsError } = await adminClient.from("admin_users").select("user_id").in("user_id", userIds);
    if (adminRowsError) return json({ error: "تعذر التحقق من صلاحيات الأعضاء." }, 500);
    const adminIds = new Set((adminRows || []).map((row: any) => row.user_id));
    return json({ members: [...found.values()].map((row) => ({
      ...row, display_name: row.display_name || "عضو بدون اسم",
      is_admin: adminIds.has(row.user_id), is_owner: row.user_id === OWNER_ID,
    })) });
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
