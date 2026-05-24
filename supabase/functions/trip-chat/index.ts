// deploy: npx supabase functions deploy trip-chat
// body: { action: 'list' | 'send', trip_id, content? }

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { createServiceClient } from "../_shared/auth.ts";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";
import { canAccessTripChat } from "../_shared/trip_access.ts";

type Action = "list" | "send";

const MAX_CONTENT_LEN = 2000;

async function insertNotification(
  service: ReturnType<typeof createClient>,
  row: Record<string, unknown>,
): Promise<void> {
  const { error } = await service.from("notifications").insert(row);
  if (error) {
    console.error("notification insert failed:", error);
  }
}

async function enrichMessages(
  supabase: ReturnType<typeof createClient>,
  rows: Record<string, unknown>[],
): Promise<Record<string, unknown>[]> {
  if (rows.length === 0) return [];

  const ids = [
    ...new Set(
      rows.map((r) => r.sender_id).filter((id): id is string => typeof id === "string"),
    ),
  ];

  const nameById = new Map<string, string>();
  if (ids.length > 0) {
    const { data: profiles } = await supabase
      .from("profiles")
      .select("id, full_name")
      .in("id", ids);
    for (const p of profiles ?? []) {
      const id = p.id as string;
      const name = (p.full_name as string)?.trim();
      nameById.set(id, name && name.length > 0 ? name : "Користувач");
    }
  }

  return rows.map((r) => ({
    ...r,
    _sender_label: nameById.get(r.sender_id as string) ?? "Учасник",
  }));
}

async function notifyTripMembers(
  service: ReturnType<typeof createClient>,
  tripId: string,
  senderId: string,
  senderName: string,
  tripTitle: string,
  preview: string,
): Promise<void> {
  const { data: trip } = await service
    .from("trips")
    .select("organizer_id, title")
    .eq("id", tripId)
    .maybeSingle();
  if (!trip) return;

  const title = (tripTitle || (trip.title as string) || "Похід").trim();
  const bodyPreview = preview.length > 120 ? `${preview.slice(0, 120)}…` : preview;

  const recipientIds = new Set<string>();

  const orgId = trip.organizer_id as string | null;
  if (orgId && orgId !== senderId) recipientIds.add(orgId);

  const { data: parts } = await service
    .from("trip_participants")
    .select("user_id")
    .eq("trip_id", tripId)
    .eq("status", "approved");

  for (const p of parts ?? []) {
    const uid = p.user_id as string;
    if (uid && uid !== senderId) recipientIds.add(uid);
  }

  for (const userId of recipientIds) {
    await insertNotification(service, {
      user_id: userId,
      type: "new_message",
      title: `Нове повідомлення: ${title}`,
      body: `${senderName}: ${bodyPreview}`,
      payload: {
        trip_id: tripId,
        trip_title: title,
        sender_id: senderId,
        sender_name: senderName,
      },
    });
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: { user }, error: userError } = await supabase.auth.getUser();
  if (userError || !user) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  let body: { action?: Action; trip_id?: string; content?: string };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const action = body.action;
  const tripId = body.trip_id;
  if (!action || !tripId) {
    return jsonResponse({ error: "action_and_trip_id_required" }, 400);
  }

  try {
    const allowed = await canAccessTripChat(supabase, user.id, tripId);
    if (!allowed) {
      return jsonResponse({ error: "forbidden", message: "Немає доступу до чату" }, 403);
    }

    if (action === "list") {
      const { data: rows, error } = await supabase
        .from("messages")
        .select("id, trip_id, sender_id, content, sent_at")
        .eq("trip_id", tripId)
        .order("sent_at", { ascending: true });
      if (error) throw error;

      const messages = await enrichMessages(
        supabase,
        (rows ?? []) as Record<string, unknown>[],
      );
      return jsonResponse({ ok: true, messages });
    }

    if (action === "send") {
      const content = body.content?.trim() ?? "";
      if (!content) {
        return jsonResponse({ error: "content_required" }, 400);
      }
      if (content.length > MAX_CONTENT_LEN) {
        return jsonResponse({ error: "content_too_long" }, 400);
      }

      const { data: inserted, error: insErr } = await supabase
        .from("messages")
        .insert({
          trip_id: tripId,
          sender_id: user.id,
          content,
        })
        .select("id, trip_id, sender_id, content, sent_at")
        .single();
      if (insErr) throw insErr;

      const service = createServiceClient();

      const { data: me } = await supabase
        .from("profiles")
        .select("full_name")
        .eq("id", user.id)
        .maybeSingle();
      const senderName = (me?.full_name as string)?.trim() || "Учасник";

      const { data: tripRow } = await supabase
        .from("trips")
        .select("title")
        .eq("id", tripId)
        .maybeSingle();

      await notifyTripMembers(
        service,
        tripId,
        user.id,
        senderName,
        (tripRow?.title as string) ?? "Похід",
        content,
      );

      const [message] = await enrichMessages(
        supabase,
        [inserted as Record<string, unknown>],
      );
      return jsonResponse({ ok: true, message });
    }

    return jsonResponse({ error: "unknown_action" }, 400);
  } catch (e) {
    console.error("trip-chat:", e);
    const msg = e instanceof Error ? e.message : "chat_failed";
    return jsonResponse({ error: "chat_failed", message: msg }, 500);
  }
});
