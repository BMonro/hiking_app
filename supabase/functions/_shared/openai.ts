export class AiNotConfiguredError extends Error {
  constructor() {
    super("AI_NOT_CONFIGURED");
    this.name = "AiNotConfiguredError";
  }
}

export async function chatCompletion(
  messages: Array<{ role: string; content: string }>,
  options?: { jsonMode?: boolean },
): Promise<string> {
  const apiKey = Deno.env.get("OPENAI_API_KEY")?.trim();
  if (!apiKey) throw new AiNotConfiguredError();

  const baseUrl = Deno.env.get("OPENAI_BASE_URL")?.trim() ||
    "https://api.openai.com/v1";
  const model = Deno.env.get("OPENAI_MODEL")?.trim() || "gpt-4o-mini";

  const body: Record<string, unknown> = {
    model,
    messages,
    temperature: 0.6,
  };
  if (options?.jsonMode) {
    body.response_format = { type: "json_object" };
  }

  const res = await fetch(`${baseUrl}/chat/completions`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`OpenAI HTTP ${res.status}: ${text.slice(0, 500)}`);
  }

  const data = await res.json();
  const content = data?.choices?.[0]?.message?.content?.trim();
  if (!content) throw new Error("Empty AI response");
  return content;
}
