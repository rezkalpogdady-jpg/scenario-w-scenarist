(function () {
  'use strict';

  if (!window.ScenarioModules) return;

  const esc = value => String(value ?? '').replace(/[&<>"']/g, ch => ({
    '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
  }[ch]));

  const statusLabel = status => ({
    draft:'مسودة محفوظة',
    pending:'قيد مراجعة الإدارة',
    approved:'تم اعتماد مشروع التخرج',
    needs_revision:'مطلوب استكمال أو تعديل'
  }[status] || 'غير محدد');

  const statusColor = status => status === 'approved' ? '#7bc69a' :
    status === 'needs_revision' ? '#e6b46b' : 'var(--muted)';

  function buildStudentPanel() {
    const academy = document.getElementById('academy');
    if (!academy || document.getElementById('academyFinalProject')) return;
    const panel = document.createElement('section');
    panel.id = 'academyFinalProject';
    panel.className = 'panel';
    panel.innerHTML = \`
      <div class="section-heading">
        <h2>مشروع التخرج النهائي</h2>
        <p>من تطوير الفكرة إلى السيناريو الجاهز للتقديم</p>
      </div>
      <p>مشروعك النهائي يجمع عناصر المنهج في عمل واحد. يمكنك حفظ مسودة والعودة إليها، ثم إرسالها للإدارة للمراجعة بعد استكمال متطلبات الأكاديمية.</p>
      <div id="capstoneEligibility" class="panel" aria-live="polite">جارٍ التحقق من تقدمك...</div>
      <div id="capstoneStudentState" class="admin-status">سجّل الدخول لحفظ مشروعك ومتابعة مراجعته.</div>
      <form id="capstoneForm">
        <label for="capstoneTitle">عنوان المشروع</label>
        <input id="capstoneTitle" maxlength="200" required placeholder="اسم الفيلم أو العمل الدرامي">
        <label for="capstoneGenre">النوع الدرامي</label>
        <input id="capstoneGenre" maxlength="80" required placeholder="دراما، تشويق، كوميديا...">
        <label for="capstoneLogline">الفكرة في سطر واحد (Logline)</label>
        <textarea id="capstoneLogline" maxlength="700" minlength="10" required placeholder="من هو البطل؟ ماذا يريد؟ وما الذي يقف في طريقه؟"></textarea>
        <label for="capstoneSynopsis">الملخص السينمائي</label>
        <textarea id="capstoneSynopsis" maxlength="6000" minlength="50" required rows="7" placeholder="اكتب ملخص القصة من البداية حتى النهاية..."></textarea>
        <label for="capstoneTreatment">المعالجة الدرامية</label>
        <textarea id="capstoneTreatment" maxlength="20000" minlength="100" required rows="12" placeholder="تطور الأحداث والشخصيات والصراع والمشاهد الرئيسية..."></textarea>
        <label for="capstoneScreenplay">السيناريو</label>
        <textarea id="capstoneScreenplay" maxlength="120000" minlength="100" required rows="18" placeholder="اكتب السيناريو بتنسيق المشاهد والحوار..."></textarea>
        <div class="admin-actions">
          <button class="btn" type="button" id="capstoneSaveDraft">حفظ كمسودة</button>
          <button class="btn primary" type="submit" id="capstoneSubmit" disabled>إرسال مشروع التخرج للمراجعة</button>
        </div>
      </form>
      <p id="capstoneMessage" aria-live="polite"></p>
      <div id="capstoneFeedback"></div>
    \`;
    academy.appendChild(panel);
  }

  function buildAdminPanel() {
    const dashboard = document.getElementById('adminDashboard');
    if (!dashboard || document.getElementById('adminAcademyFinalProjects')) return;
    const panel = document.createElement('section');
    panel.className = 'panel';
    panel.id = 'adminAcademyFinalProjects';
    panel.innerHTML = \`
      <div class="section-heading">
        <h2>مراجعة مشروعات التخرج</h2>
        <p>اعتماد المشروع أو إعادته للطالب لاستكمال التعديلات</p>
      </div>
      <div id="adminFinalProjectsList" class="grid"><div class="panel">تظهر المشروعات المرسلة هنا.</div></div>
    \`;
    const assignments = document.getElementById('adminAcademyAssignments');
    if (assignments && assignments.parentElement) assignments.parentElement.insertBefore(panel, assignments.nextSibling);
    else dashboard.appendChild(panel);
  }

  function getFormData() {
    return {
      project_title: document.getElementById('capstoneTitle').value.trim(),
      genre: document.getElementById('capstoneGenre').value.trim(),
      logline: document.getElementById('capstoneLogline').value.trim(),
      synopsis: document.getElementById('capstoneSynopsis').value.trim(),
      treatment: document.getElementById('capstoneTreatment').value.trim(),
      screenplay: document.getElementById('capstoneScreenplay').value.trim()
    };
  }

  function fillForm(project) {
    const fields = {
      capstoneTitle: project?.project_title,
      capstoneGenre: project?.genre,
      capstoneLogline: project?.logline,
      capstoneSynopsis: project?.synopsis,
      capstoneTreatment: project?.treatment,
      capstoneScreenplay: project?.screenplay
    };
    Object.entries(fields).forEach(([id,value]) => {
      const el = document.getElementById(id);
      if (el) el.value = value || '';
    });
  }

  function setFormLocked(locked) {
    ['capstoneTitle','capstoneGenre','capstoneLogline','capstoneSynopsis','capstoneTreatment','capstoneScreenplay']
      .forEach(id => { const el=document.getElementById(id); if(el) el.disabled=locked; });
    const draft=document.getElementById('capstoneSaveDraft');
    const submit=document.getElementById('capstoneSubmit');
    if (draft) draft.disabled=locked;
    if (submit) submit.disabled=locked || submit.dataset.eligible !== 'yes';
  }

  async function loadStudent() {
    const state=document.getElementById('capstoneStudentState');
    const eligibility=document.getElementById('capstoneEligibility');
    const form=document.getElementById('capstoneForm');
    const feedback=document.getElementById('capstoneFeedback');
    if (!state || !eligibility || !form) return;

    if (!accountUser) {
      state.textContent='سجّل الدخول أولًا حتى تحفظ مشروعك.';
      eligibility.textContent='يمكنك الاطلاع على متطلبات المشروع، لكن الحفظ والإرسال متاحان للأعضاء المسجلين.';
      form.style.display='none';
      return;
    }
    form.style.display='block';

    try {
      const client=accountClient();
      const [progressResult, assignmentsResult, projectResult] = await Promise.all([
        client.from('academy_progress').select('lesson_number').eq('user_id',accountUser.id).eq('completed',true),
        client.from('academy_assignments').select('lesson_number,status').eq('user_id',accountUser.id),
        client.from('academy_final_projects').select('*').eq('user_id',accountUser.id).maybeSingle()
      ]);
      if (progressResult.error) throw progressResult.error;
      if (assignmentsResult.error) throw assignmentsResult.error;
      if (projectResult.error) throw projectResult.error;

      const completed=new Set((progressResult.data||[]).map(row=>row.lesson_number));
      const approved=new Set((assignmentsResult.data||[]).filter(row=>row.status==='approved').map(row=>row.lesson_number));
      const lessonCount=completed.size;
      const approvedCount=approved.size;
      const eligible=lessonCount===30 && approvedCount===30;
      eligibility.innerHTML=\`<strong>متطلبات إرسال مشروع التخرج</strong><p>المحاضرات المكتملة: \${lessonCount} من 30</p><p>التدريبات التي وافقت عليها الإدارة: \${approvedCount} من 30</p><p style="color:\${eligible?'#7bc69a':'var(--muted)'}">\${eligible?'اكتملت المتطلبات. يمكنك إرسال مشروعك للمراجعة.':'يمكنك حفظ مسودة الآن، وسيُفتح الإرسال النهائي بعد إتمام المحاضرات الثلاثين واعتماد التدريبات الثلاثين.'}</p>\`;
      const submit=document.getElementById('capstoneSubmit');
      if (submit) { submit.dataset.eligible=eligible?'yes':'no'; submit.disabled=!eligible; }

      const project=projectResult.data;
      if (project) {
        fillForm(project);
        state.innerHTML=\`حالة المشروع: <strong style="color:\${statusColor(project.status)}">\${statusLabel(project.status)}</strong> • آخر تحديث: \${new Date(project.updated_at).toLocaleString('ar-EG')}\`;
        if (feedback) feedback.innerHTML=project.admin_feedback ? \`<div class="panel"><strong>ملاحظات الإدارة</strong><p style="white-space:pre-wrap">\${esc(project.admin_feedback)}</p></div>\` : '';
        setFormLocked(project.status==='pending' || project.status==='approved');
      } else {
        state.textContent='لم تحفظ مشروع تخرج بعد. يمكنك البدء وحفظ مسودة.';
        if (feedback) feedback.innerHTML='';
        setFormLocked(false);
      }
    } catch(error) {
      state.textContent='تعذر تحميل مشروعك: '+(error.message||'تحقق من اتصالك.');
    }
  }

  async function saveStudent(status) {
    const message=document.getElementById('capstoneMessage');
    if (!accountUser) { if(message)message.textContent='سجّل الدخول أولًا.'; return; }
    const data=getFormData();
    const required=[
      ['project_title',2,200,'عنوان المشروع'],
      ['genre',2,80,'النوع الدرامي'],
      ['logline',10,700,'الفكرة في سطر واحد'],
      ['synopsis',50,6000,'الملخص السينمائي'],
      ['treatment',100,20000,'المعالجة الدرامية'],
      ['screenplay',100,120000,'السيناريو']
    ];
    for (const [key,min,max,label] of required) {
      if (data[key].length<min || data[key].length>max) {
        if(message)message.textContent=\`راجع حقل "\${label}"؛ الطول المطلوب من \${min} إلى \${max} حرفًا.\`;
        return;
      }
    }
    if (status==='pending') {
      const button=document.getElementById('capstoneSubmit');
      if (!button || button.dataset.eligible!=='yes') {
        if(message)message.textContent='أكمل المحاضرات الثلاثين واحصل على اعتماد التدريبات الثلاثين أولًا.';
        return;
      }
    }
    const payload={...data,user_id:accountUser.id,status,submitted_at:new Date().toISOString(),updated_at:new Date().toISOString(),admin_feedback:null,reviewed_at:null};
    try {
      if(message)message.textContent=status==='draft'?'جارٍ حفظ المسودة...':'جارٍ إرسال المشروع للمراجعة...';
      const {error}=await accountClient().from('academy_final_projects').upsert(payload,{onConflict:'user_id'});
      if(error)throw error;
      if(message)message.textContent=status==='draft'?'تم حفظ المسودة. يمكنك العودة لاستكمالها لاحقًا.':'تم إرسال مشروع التخرج إلى الإدارة بنجاح.';
      await loadStudent();
    } catch(error) {
      if(message)message.textContent='تعذر حفظ المشروع: '+(error.message||'حاول مرة أخرى.');
    }
  }

  async function loadAdmin() {
    if (!adminSupabase || !adminSession) return;
    const box=document.getElementById('adminFinalProjectsList');
    if (!box) return;
    box.innerHTML='<div class="panel">جارٍ تحميل مشروعات التخرج...</div>';
    const {data,error}=await adminSupabase.from('academy_final_projects')
      .select('id,user_id,project_title,genre,logline,synopsis,treatment,screenplay,status,admin_feedback,submitted_at')
      .order('submitted_at',{ascending:false}).limit(100);
    if(error){box.textContent='تعذر تحميل المشروعات: '+error.message;return;}
    if(!data?.length){box.innerHTML='<div class="panel">لا توجد مشروعات تخرج مرسلة حتى الآن.</div>';return;}
    const ids=[...new Set(data.map(item=>item.user_id))];
    const profiles=await adminSupabase.from('member_profiles').select('user_id,display_name').in('user_id',ids);
    const names=new Map((profiles.data||[]).map(row=>[row.user_id,row.display_name]));
    box.innerHTML=data.map(item=>\`
      <article class="admin-item">
        <h3>\${esc(item.project_title)}</h3>
        <p class="admin-status">الطالب: \${esc(names.get(item.user_id)||'عضو')} • \${esc(item.genre)} • \${statusLabel(item.status)}</p>
        <p><strong>الفكرة:</strong> \${esc(item.logline)}</p>
        <details><summary>قراءة الملخص والمعالجة والسيناريو</summary>
          <h4>الملخص السينمائي</h4><div style="white-space:pre-wrap">\${esc(item.synopsis)}</div>
          <h4>المعالجة الدرامية</h4><div style="white-space:pre-wrap">\${esc(item.treatment)}</div>
          <h4>السيناريو</h4><div style="white-space:pre-wrap;max-height:520px;overflow:auto;background:#101010;padding:12px;border-radius:8px">\${esc(item.screenplay)}</div>
        </details>
        <label for="capstoneFeedback-\${item.id}">ملاحظات الإدارة</label>
        <textarea id="capstoneFeedback-\${item.id}" rows="4" maxlength="6000">\${esc(item.admin_feedback||'')}</textarea>
        <div class="admin-actions">
          <button class="btn primary" type="button" data-capstone-action="approved" data-id="\${item.id}">اعتماد مشروع التخرج</button>
          <button class="btn" type="button" data-capstone-action="needs_revision" data-id="\${item.id}">إعادة للطالب للتعديل</button>
        </div>
        <small>\${new Date(item.submitted_at).toLocaleString('ar-EG')}</small>
      </article>\`).join('');
    box.querySelectorAll('[data-capstone-action]').forEach(button=>{
      button.addEventListener('click',async()=>{
        const id=button.dataset.id;
        const status=button.dataset.capstoneAction;
        const feedback=document.getElementById('capstoneFeedback-'+id)?.value.trim()||null;
        if(status==='needs_revision'&&!feedback){alert('اكتب ملاحظات توضح ما يحتاج إلى تعديل.');return;}
        button.disabled=true;
        const {error}=await adminSupabase.from('academy_final_projects').update({
          status,admin_feedback:feedback,reviewed_at:new Date().toISOString(),updated_at:new Date().toISOString()
        }).eq('id',id);
        if(error){alert('تعذرت مراجعة المشروع: '+error.message);button.disabled=false;return;}
        await loadAdmin();
      });
    });
  }

  async function init() {
    buildStudentPanel();
    buildAdminPanel();
    document.getElementById('capstoneSaveDraft')?.addEventListener('click',()=>saveStudent('draft'));
    document.getElementById('capstoneForm')?.addEventListener('submit',event=>{
      event.preventDefault();
      saveStudent('pending');
    });
    await loadStudent();
    if (adminSession) await loadAdmin();

    try {
      accountClient().auth.onAuthStateChange((event,session)=>{
        if (event==='SIGNED_IN' || event==='SIGNED_OUT' || event==='TOKEN_REFRESHED') {
          Promise.resolve().then(()=>loadStudent());
        }
      });
    } catch (_) {}

    const dashboard=document.getElementById('adminDashboard');
    if (dashboard && window.MutationObserver) {
      const observer=new MutationObserver(()=>{
        if (adminSession && dashboard.style.display!=='none') loadAdmin();
      });
      observer.observe(dashboard,{attributes:true,attributeFilter:['style']});
    }
  }

  window.ScenarioModules.register('academy-capstone', init);
})();