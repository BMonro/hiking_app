

import { createUserClient } from "../_shared/auth.ts";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { AiNotConfiguredError, chatCompletion } from "../_shared/openai.ts";
import { buildProfileContext } from "../_shared/profile.ts";

interface ChatMessage {
  role: string;
  content: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const auth = await createUserClient(req);
  if (auth instanceof Response) return auth;
  const { supabase, userId } = auth;

  let body: { ping?: boolean; messages?: ChatMessage[] };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  if (body.ping === true) {
    try {
      if (!Deno.env.get("OPENAI_API_KEY")?.trim()) {
        return jsonResponse({ error: "ai_not_configured" }, 503);
      }
      return jsonResponse({ ok: true });
    } catch {
      return jsonResponse({ error: "ai_not_configured" }, 503);
    }
  }

  const messages = body.messages;
  if (!Array.isArray(messages) || messages.length === 0) {
    return jsonResponse({ error: "messages_required" }, 400);
  }

  const sanitized = messages
    .filter((m) =>
      (m.role === "user" || m.role === "assistant") &&
      typeof m.content === "string" &&
      m.content.trim().length > 0
    )
    .slice(-20)
    .map((m) => ({ role: m.role, content: m.content.trim() }));

  try {
    const profileContext = await buildProfileContext(supabase, userId);
    const system = `Ти дружній україномовний порадник з пішохідного туризму в застосунку HikingApp.
Давай практичні, безпечні поради щодо спорядження, підготовки, харчування, погоди, темпу на стежці.
Враховуй профіль користувача нижче. Не вигадуй конкретних GPS-координат.
Якщо питання про медицину — рекомендуй звернутися до лікаря.
Відповідай стисло (до 6 речень), структуровано за потреби.

Профіль:
${profileContext}`;

    const reply = await chatCompletion([
      { role: "system", content: system },
      ...sanitized,
    ]);

    return jsonResponse({ reply });
  } catch (e) {
    if (e instanceof AiNotConfiguredError) {
      return jsonResponse({ error: "ai_not_configured" }, 503);
    }
    console.error("ai-chat error:", e);
    return jsonResponse({ error: "ai_request_failed" }, 502);
  }
});
