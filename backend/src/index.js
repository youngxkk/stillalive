/**
 * Cloudflare Worker Logic
 * 包含两个部分：
 * 1. fetch: 处理来自 iOS App 的 HTTP 请求
 *    - POST /checkin     打卡（重置计时）
 *    - POST /update      只更新联系人/邮件内容/间隔，不重置计时
 *    - POST /deregister  停止监控，删除记录
 *    - POST /test        立即发送一封测试邮件（服务端限流）
 *    - POST /outing/start 开始出门守护（同时算一次打卡），到预计返回时间还没结束就告警
 *    - POST /outing/end   结束出门守护（同时算一次打卡）
 * 2. scheduled: 定时任务，检查是否超时并发送邮件
 *
 * 告警发出后用户再打卡（或结束守护），会给收到告警的联系人补发一封「警报解除」邮件。
 *
 * 身份：每台设备在 Keychain 中保存 deviceId + deviceSecret。
 * 第一次请求时服务端保存 secret 的 SHA-256，之后的请求必须携带同一个 secret。
 */

const MIN_INTERVAL_HOURS = 1;
const MAX_INTERVAL_HOURS = 24 * 30;
const MAX_SUBJECT_LENGTH = 200;
const MAX_BODY_LENGTH = 5000;
const DAY_SECONDS = 24 * 60 * 60;
// 同一个收件邮箱 24 小时内最多收到的告警邮件数，防止被滥用来轰炸某个邮箱
const MAX_ALERTS_PER_EMAIL_PER_DAY = 3;
const MIN_OUTING_MINUTES = 10;
const MAX_OUTING_MINUTES = 48 * 60;

const DEFAULT_ALL_CLEAR_SUBJECT = "All clear: I'm OK now / 警报解除：我已经报平安了";
const DEFAULT_ALL_CLEAR_BODY = "I have just checked in on my 'Are You OK' app. Sorry for the earlier alert, I'm safe.\n---\n我刚刚在 Are You OK App 上报了平安。之前的警报可以解除了，我很安全。";

const EMAIL_REGEX = /^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,64}$/;
const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export default {
  // 1. HTTP 接口
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // 只允许 POST 请求
    if (request.method !== "POST") {
      return new Response("Only POST allowed", { status: 405 });
    }

    let data;
    try {
      data = await request.json();
    } catch (err) {
      return jsonResponse({ success: false, message: "Invalid JSON" }, 400);
    }
    if (!data || typeof data !== "object") {
      return jsonResponse({ success: false, message: "Invalid JSON" }, 400);
    }

    try {
      switch (url.pathname) {
        case "/checkin":
          // 旧版本 (1.1) 客户端没有 deviceId，走兼容逻辑
          if (data.deviceId === undefined) {
            return await handleLegacyCheckIn(env, data);
          }
          return await handleCheckIn(env, data);
        case "/update":
          return await handleUpdate(env, data);
        case "/deregister":
          return await handleDeregister(env, data);
        case "/test":
          return await handleTest(env, data);
        case "/outing/start":
          return await handleOutingStart(env, data);
        case "/outing/end":
          return await handleOutingEnd(env, data);
        default:
          return new Response("Not Found", { status: 404 });
      }
    } catch (err) {
      console.error("Request failed:", err);
      return jsonResponse({ success: false, message: "Internal error" }, 500);
    }
  },

  // 2. 定时任务 (Cron Job)
  async scheduled(event, env, ctx) {
    console.log("Cron trigger started...");

    let totalProcessed = 0;
    for (const prefix of ["device:", "user:"]) {
      let cursor = undefined;
      do {
        // Cloudflare KV list api with pagination
        const list = await env.STATUS_STORE.list({ prefix, cursor });

        for (const key of list.keys) {
          await processRecord(env, key);
          totalProcessed++;
        }

        cursor = list.list_complete ? undefined : list.cursor;
      } while (cursor);
    }

    console.log(`Cron trigger finished. Total records processed: ${totalProcessed}`);
  }
};

// MARK: - Handlers

async function handleCheckIn(env, data) {
  const auth = await authenticate(env, data, { allowCreate: true });
  if (auth.error) return auth.error;

  const fields = validateConfig(data);
  if (fields.error) return fields.error;

  const { record, allClearSent } = await checkInRecord(env, auth, fields, data);
  await putRecord(env, auth.key, record);

  // 升级到新版本后，删除旧版本以联系人邮箱为键的记录，避免它过期后误发告警
  await env.STATUS_STORE.delete(`user:${fields.targetEmail}`);

  return jsonResponse({ success: true, message: "Check-in successful", allClearSent });
}

async function handleOutingStart(env, data) {
  const auth = await authenticate(env, data, { allowCreate: true });
  if (auth.error) return auth.error;

  const fields = validateConfig(data);
  if (fields.error) return fields.error;

  const outing = validateOuting(data);
  if (outing.error) return outing.error;

  const { record, allClearSent } = await checkInRecord(env, auth, fields, data);
  record.outing = {
    deadline: Date.now() + outing.minutes * 60 * 1000,
    subject: outing.subject,
    body: outing.body,
    hasSentEmail: false
  };
  await putRecord(env, auth.key, record);
  await env.STATUS_STORE.delete(`user:${fields.targetEmail}`);

  return jsonResponse({ success: true, message: "Outing started", deadline: record.outing.deadline, allClearSent });
}

async function handleOutingEnd(env, data) {
  const auth = await authenticate(env, data, { allowCreate: false });
  if (auth.error) {
    // 没有记录也就没有在进行的守护
    if (auth.notFound) return jsonResponse({ success: true, message: "Not registered", allClearSent: false });
    return auth.error;
  }

  const fields = validateConfig(data);
  if (fields.error) return fields.error;

  const { record, allClearSent } = await checkInRecord(env, auth, fields, data);
  record.outing = null;
  await putRecord(env, auth.key, record);

  return jsonResponse({ success: true, message: "Outing ended", allClearSent });
}

async function handleUpdate(env, data) {
  const auth = await authenticate(env, data, { allowCreate: false });
  if (auth.error) return auth.error;

  const fields = validateConfig(data);
  if (fields.error) return fields.error;

  const record = auth.record;
  const emailChanged = record.targetEmail !== fields.targetEmail;
  record.intervalHours = fields.intervalHours;
  record.targetEmail = fields.targetEmail;
  record.subject = fields.subject;
  record.body = fields.body;
  // 换了联系人后，新联系人还没收到过告警
  if (emailChanged) {
    record.hasSentEmail = false;
  }
  await putRecord(env, auth.key, record);

  return jsonResponse({ success: true, message: "Updated" });
}

async function handleDeregister(env, data) {
  const auth = await authenticate(env, data, { allowCreate: false });
  if (auth.error) {
    // 记录本来就不存在，视为成功
    if (auth.notFound) return jsonResponse({ success: true, message: "Not registered" });
    return auth.error;
  }

  await env.STATUS_STORE.delete(auth.key);
  return jsonResponse({ success: true, message: "Deregistered" });
}

async function handleTest(env, data) {
  const auth = await authenticate(env, data, { allowCreate: true });
  if (auth.error) return auth.error;

  const fields = validateConfig({ ...data, intervalHours: MIN_INTERVAL_HOURS });
  if (fields.error) return fields.error;

  // 服务端限流：每台设备、每个收件邮箱 24 小时内各一封测试邮件
  const deviceLimitKey = `ratelimit:test:device:${auth.deviceId}`;
  const emailLimitKey = `ratelimit:test:email:${fields.targetEmail}`;
  const [deviceLimited, emailLimited] = await Promise.all([
    env.STATUS_STORE.get(deviceLimitKey),
    env.STATUS_STORE.get(emailLimitKey)
  ]);
  if (deviceLimited || emailLimited) {
    return jsonResponse({ success: false, message: "Test email limit reached" }, 429);
  }

  console.log(`Sending test email to ${fields.targetEmail}...`);
  const emailSuccess = await sendEmail(env, {
    targetEmail: fields.targetEmail,
    subject: fields.subject,
    body: fields.body,
    footer: dailyAlertFooter(fields.intervalHours)
  });

  if (!emailSuccess) {
    return jsonResponse({ success: false, message: "Failed to send test email" }, 500);
  }

  await Promise.all([
    env.STATUS_STORE.put(deviceLimitKey, "1", { expirationTtl: DAY_SECONDS }),
    env.STATUS_STORE.put(emailLimitKey, "1", { expirationTtl: DAY_SECONDS })
  ]);
  return jsonResponse({ success: true, message: "Test email sent" });
}

// 兼容 1.1 版本客户端：以联系人邮箱为键，不支持测试邮件。
// 等用户都升级后可以删除这段逻辑。
async function handleLegacyCheckIn(env, data) {
  if (data.isTest) {
    return jsonResponse({ success: false, message: "Please update the app to send test emails" }, 410);
  }

  const fields = validateConfig(data);
  if (fields.error) return fields.error;

  const record = {
    lastCheckIn: Date.now(),
    intervalHours: fields.intervalHours,
    targetEmail: fields.targetEmail,
    subject: fields.subject,
    body: fields.body,
    status: "safe",
    hasSentEmail: false
  };
  await putRecord(env, `user:${fields.targetEmail}`, record);

  return jsonResponse({ success: true, message: "Check-in successful" });
}

// MARK: - Cron

async function processRecord(env, key) {
  const now = Date.now();
  const meta = key.metadata;

  // 有 metadata 时先用它判断，避免每条记录都读一次 KV
  if (meta && typeof meta.lastCheckIn === "number") {
    const dailyDue = !meta.hasSentEmail && now > expirationTime(meta);
    const outingDue = typeof meta.outingDeadline === "number" && !meta.outingSent && now > meta.outingDeadline;
    if (!dailyDue && !outingDue) return;
  }

  const userRecordStr = await env.STATUS_STORE.get(key.name);
  if (!userRecordStr) return;

  let userRecord;
  try {
    userRecord = JSON.parse(userRecordStr);
  } catch (err) {
    console.error(`Corrupt record ${key.name}`);
    return;
  }

  let changed = false;

  // 日常打卡超时，且还没发过邮件
  if (now > expirationTime(userRecord) && !userRecord.hasSentEmail) {
    const sent = await sendAlert(env, key.name, {
      targetEmail: userRecord.targetEmail,
      subject: userRecord.subject,
      body: userRecord.body,
      footer: dailyAlertFooter(userRecord.intervalHours)
    });
    if (sent) {
      // 更新状态为已发送，避免重复发送
      userRecord.hasSentEmail = true;
      userRecord.status = "danger";
      changed = true;
    }
  }

  // 出门守护超过预计返回时间
  const outing = userRecord.outing;
  if (outing && !outing.hasSentEmail && now > outing.deadline) {
    const sent = await sendAlert(env, key.name, {
      targetEmail: userRecord.targetEmail,
      subject: outing.subject,
      body: outing.body,
      footer: "This alert was triggered because the user did not mark themselves safe before their expected return time."
    });
    if (sent) {
      outing.hasSentEmail = true;
      changed = true;
    }
  }

  if (changed) {
    // 用户之后再报平安时，给这个邮箱补发警报解除邮件
    userRecord.pendingAllClear = userRecord.targetEmail;
    await putRecord(env, key.name, userRecord);
  }
}

// 发送告警邮件，受每个收件邮箱每天的告警次数限制
async function sendAlert(env, keyName, email) {
  const alertLimitKey = `ratelimit:alert:${email.targetEmail}`;
  const alertCount = parseInt(await env.STATUS_STORE.get(alertLimitKey) || "0", 10);
  if (alertCount >= MAX_ALERTS_PER_EMAIL_PER_DAY) {
    console.warn(`Alert limit reached for ${email.targetEmail}, skipping ${keyName}`);
    return false;
  }

  console.log(`Sending email for ${email.targetEmail}...`);
  const emailSuccess = await sendEmail(env, email);
  if (emailSuccess) {
    await env.STATUS_STORE.put(alertLimitKey, String(alertCount + 1), { expirationTtl: DAY_SECONDS });
  }
  return emailSuccess;
}

function dailyAlertFooter(intervalHours) {
  return `This alert was triggered because the user failed to check in within their set interval (${intervalHours} hours).`;
}

function expirationTime(record) {
  // 计算截止时间 (毫秒)
  return record.lastCheckIn + (record.intervalHours * 60 * 60 * 1000);
}

// MARK: - Check-in

// 生成一次打卡后的记录：重置计时，保留未到期的出门守护；
// 如果之前发过告警，顺便给联系人发警报解除邮件。
async function checkInRecord(env, auth, fields, data) {
  const previous = auth.record || {};
  const now = Date.now();

  const record = {
    lastCheckIn: now, // 当前时间毫秒
    intervalHours: fields.intervalHours,
    targetEmail: fields.targetEmail, // 接收告警的邮箱
    subject: fields.subject,
    body: fields.body,
    status: "safe", // 当前状态
    hasSentEmail: false, // 标记是否已发送过邮件，防止重复发送
    secretHash: auth.secretHash,
    // 已经过了预计返回时间的守护，打卡后就结束了
    outing: previous.outing && now <= previous.outing.deadline ? previous.outing : null
  };

  let allClearSent = false;
  if (previous.pendingAllClear) {
    console.log(`Sending all-clear email to ${previous.pendingAllClear}...`);
    allClearSent = await sendEmail(env, {
      targetEmail: previous.pendingAllClear,
      subject: messageField(data.allClearSubject, DEFAULT_ALL_CLEAR_SUBJECT, MAX_SUBJECT_LENGTH).replace(/[\r\n]+/g, " ").trim(),
      body: messageField(data.allClearBody, DEFAULT_ALL_CLEAR_BODY, MAX_BODY_LENGTH),
      heading: "All Clear",
      accentColor: "#00F260",
      footer: "This follows an earlier alert from the same user, who has now checked in."
    });
    // 发送失败就留着，下次打卡再试
    if (!allClearSent) record.pendingAllClear = previous.pendingAllClear;
  }

  return { record, allClearSent };
}

// MARK: - Helpers

async function authenticate(env, data, { allowCreate }) {
  const { deviceId, deviceSecret } = data;
  if (typeof deviceId !== "string" || !UUID_REGEX.test(deviceId) ||
      typeof deviceSecret !== "string" || deviceSecret.length < 32 || deviceSecret.length > 128) {
    return { error: jsonResponse({ success: false, message: "Missing or invalid device credentials" }, 400) };
  }

  const key = `device:${deviceId.toLowerCase()}`;
  const secretHash = await sha256Hex(deviceSecret);
  const existingStr = await env.STATUS_STORE.get(key);

  if (!existingStr) {
    if (!allowCreate) {
      return { notFound: true, error: jsonResponse({ success: false, message: "Not registered" }, 404) };
    }
    return { key, deviceId: deviceId.toLowerCase(), secretHash, record: null };
  }

  const record = JSON.parse(existingStr);
  if (record.secretHash !== secretHash) {
    return { error: jsonResponse({ success: false, message: "Unauthorized" }, 401) };
  }
  return { key, deviceId: deviceId.toLowerCase(), secretHash, record };
}

function validateConfig(data) {
  if (typeof data.email !== "string") {
    return { error: jsonResponse({ success: false, message: "Missing email" }, 400) };
  }
  const targetEmail = data.email.trim().toLowerCase();
  if (!EMAIL_REGEX.test(targetEmail)) {
    return { error: jsonResponse({ success: false, message: "Invalid email" }, 400) };
  }

  const interval = Number(data.intervalHours);
  if (!Number.isFinite(interval) || interval <= 0) {
    return { error: jsonResponse({ success: false, message: "Missing or invalid intervalHours" }, 400) };
  }
  // 不允许过短的间隔（否则可以用来立刻给任意邮箱发信）
  const intervalHours = Math.min(Math.max(interval, MIN_INTERVAL_HOURS), MAX_INTERVAL_HOURS);

  const subject = (typeof data.subject === "string" && data.subject.trim()) ? data.subject : "Emergency Alert";
  const body = (typeof data.body === "string" && data.body.trim()) ? data.body : "I have not checked in.";
  if (subject.length > MAX_SUBJECT_LENGTH || body.length > MAX_BODY_LENGTH) {
    return { error: jsonResponse({ success: false, message: "Subject or body too long" }, 400) };
  }

  return {
    targetEmail,
    intervalHours,
    // 主题去掉换行，防止邮件头注入
    subject: subject.replace(/[\r\n]+/g, " ").trim(),
    body
  };
}

function validateOuting(data) {
  const minutes = Number(data.outingMinutes);
  if (!Number.isFinite(minutes) || minutes <= 0) {
    return { error: jsonResponse({ success: false, message: "Missing or invalid outingMinutes" }, 400) };
  }
  if (typeof data.outingSubject !== "string" || !data.outingSubject.trim() ||
      typeof data.outingBody !== "string" || !data.outingBody.trim()) {
    return { error: jsonResponse({ success: false, message: "Missing outing message" }, 400) };
  }
  if (data.outingSubject.length > MAX_SUBJECT_LENGTH || data.outingBody.length > MAX_BODY_LENGTH) {
    return { error: jsonResponse({ success: false, message: "Subject or body too long" }, 400) };
  }

  return {
    minutes: Math.min(Math.max(minutes, MIN_OUTING_MINUTES), MAX_OUTING_MINUTES),
    subject: data.outingSubject.replace(/[\r\n]+/g, " ").trim(),
    body: data.outingBody
  };
}

// 可选的文本字段：缺失、为空或过长时用默认值
function messageField(value, fallback, maxLength) {
  if (typeof value !== "string" || !value.trim() || value.length > maxLength) return fallback;
  return value;
}

async function putRecord(env, key, record) {
  // 把 cron 需要的字段放进 metadata，list 时就能拿到
  const metadata = {
    lastCheckIn: record.lastCheckIn,
    intervalHours: record.intervalHours,
    hasSentEmail: record.hasSentEmail
  };
  if (record.outing) {
    metadata.outingDeadline = record.outing.deadline;
    metadata.outingSent = record.outing.hasSentEmail;
  }
  await env.STATUS_STORE.put(key, JSON.stringify(record), { metadata });
}

async function sha256Hex(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, "0")).join("");
}

function escapeHtml(text) {
  return String(text)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function jsonResponse(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json" }
  });
}

// 辅助函数：发送邮件 (使用 Resend API)
// email: { targetEmail, subject, body, footer, heading?, accentColor? }
async function sendEmail(env, email) {
  const heading = email.heading || "Emergency Alert";
  const accentColor = email.accentColor || "#00F260";
  // 这里的 RESEND_API_KEY 需要在 wrangler secret 中设置
  if (!env.RESEND_API_KEY) {
    console.error("Missing RESEND_API_KEY");
    return false;
  }

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${env.RESEND_API_KEY}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      from: "Are You OK App <alert@maxc.cc>",
      to: [email.targetEmail],
      subject: email.subject,
      // 纯文本版本，方便不显示 HTML 的客户端
      text: `${email.body}\n\n--\nSent automatically by Are You OK App Server.`,
      html: `
        <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #f0f0f0; border-radius: 12px; background-color: #ffffff;">
          <h2 style="color: #333; border-bottom: 2px solid ${accentColor}; padding-bottom: 10px;">${escapeHtml(heading)}</h2>
          <p style="font-size: 16px; line-height: 1.6; color: #555;">
            ${escapeHtml(email.body).replace(/\n/g, '<br>')}
          </p>
          <div style="margin-top: 30px; padding-top: 20px; border-top: 1px solid #eee; font-size: 12px; color: #999;">
            <p>Sent automatically by <strong>Are You OK</strong> App Server.</p>
            <p>${escapeHtml(email.footer)}</p>
          </div>
        </div>
      `
    })
  });

  if (res.ok) {
    console.log("Email sent successfully!");
    return true;
  } else {
    try {
      const errText = await res.text();
      console.error("Failed to send email:", errText);
    } catch (e) {
      console.error("Failed to send email (unknown error)");
    }
    return false;
  }
}
