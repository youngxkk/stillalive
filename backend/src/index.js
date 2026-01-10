/**
 * Cloudflare Worker Logic
 * 包含两个部分：
 * 1. fetch: 处理来自 iOS App 的 HTTP 请求 (Check-in)
 * 2. scheduled: 定时任务，检查是否超时并发送邮件
 */

export default {
  // 1. HTTP 接口
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // 只允许 POST 请求
    if (request.method !== "POST") {
      return new Response("Only POST allowed", { status: 405 });
    }

    // 路由: /checkin
    if (url.pathname === "/checkin") {
      try {
        const data = await request.json();

        // 必需字段验证
        if (!data.email || data.intervalHours === undefined) {
          return new Response("Missing email or intervalHours", { status: 400 });
        }

        // 如果是测试请求，立即发送邮件且不存入 KV (或者存入但标记为测试)
        if (data.isTest) {
          console.log(`Sending test email to ${data.email}...`);
          const emailSuccess = await sendEmail(env, {
            targetEmail: data.email,
            subject: data.subject || "Test Email",
            body: data.body || "This is a test."
          });

          if (emailSuccess) {
            return new Response(JSON.stringify({ success: true, message: "Test email sent" }), {
              headers: { "Content-Type": "application/json" }
            });
          } else {
            return new Response(JSON.stringify({ success: false, message: "Failed to send test email" }), {
              status: 500,
              headers: { "Content-Type": "application/json" }
            });
          }
        }

        // 构建存储对象
        const statusRecord = {
          lastCheckIn: Date.now(), // 当前时间毫秒
          intervalHours: data.intervalHours,
          targetEmail: data.email, // 接收告警的邮箱
          subject: data.subject || "Emergency Alert",
          body: data.body || "I have not checked in.",
          status: "safe", // 当前状态
          hasSentEmail: false // 标记是否已发送过邮件，防止重复发送
        };

        // 存入 KV 数据库
        await env.STATUS_STORE.put(`user:${data.email}`, JSON.stringify(statusRecord));

        return new Response(JSON.stringify({ success: true, message: "Check-in successful" }), {
          headers: { "Content-Type": "application/json" }
        });

      } catch (err) {
        return new Response(`Error: ${err.message}`, { status: 500 });
      }
    }

    return new Response("Not Found", { status: 404 });
  },

  // 2. 定时任务 (Cron Job)
  async scheduled(event, env, ctx) {
    console.log("Cron trigger started...");

    // 获取所有用户数据 (简单版：生产环境可能需要分页 list)
    // Cloudflare KV list api
    const list = await env.STATUS_STORE.list({ prefix: "user:" });

    for (const key of list.keys) {
      const userRecordStr = await env.STATUS_STORE.get(key.name);
      if (!userRecordStr) continue;

      let userRecord = JSON.parse(userRecordStr);
      const now = Date.now();

      // 计算截止时间 (毫秒)
      const expirationTime = userRecord.lastCheckIn + (userRecord.intervalHours * 60 * 60 * 1000);

      // 检查是否超时
      if (now > expirationTime) {
        // 已经超时，检查是否已经发过邮件
        if (!userRecord.hasSentEmail) {
          console.log(`Sending email for ${userRecord.targetEmail}...`);

          const emailSuccess = await sendEmail(env, userRecord);

          if (emailSuccess) {
            // 更新状态为已发送，避免每10分钟发一次轰炸
            userRecord.hasSentEmail = true;
            userRecord.status = "danger";
            await env.STATUS_STORE.put(key.name, JSON.stringify(userRecord));
          }
        }
      } else {
        // 如果用户及时 check-in 了，状态应该是 safe，这在 fetch 里已经更新了
        // 这里不需要做什么
      }
    }
  }
};

// 辅助函数：发送邮件 (使用 Resend API)
async function sendEmail(env, userRecord) {
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
      from: "Are You OK APP <onboarding@resend.dev>", // 免费测试账号只能用这个发
      to: [userRecord.targetEmail], // 必须是你注册 Resend 时验证过的邮箱 (测试版限制)
      subject: userRecord.subject,
      html: `<p>${userRecord.body}</p><br><p>Sent automatically by Are You OK App Server.</p>`
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
