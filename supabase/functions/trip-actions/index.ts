// deploy: npx supabase functions deploy trip-actions
// actions: apply | decide | cancel | create | update | close | complete | leave

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { createServiceClient } from "../_shared/auth.ts";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

type Action =
  | "apply"
  | "decide"
  | "cancel"
  | "create"
  | "update"
  | "close"
  | "complete"
  | "leave";

const fitnessUa: Record<string, string> = {
  beginner: "початківець",
  intermediate: "середній",
  advanced: "досвідчений",
};

function formatDates(trip: { start_date?: string; end_date?: string }): string {
  const s = trip.start_date ?? "";
  const e = trip.end_date ?? "";
  if (s && e && s !== e) return `${s} — ${e}`;
  return s || e || "";
}

function generateTripCode(): string {
  const n = Date.now().toString();
  return `TRIP-${n.slice(-8)}`;
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

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const action = body.action as Action | undefined;
  if (!action) {
    return jsonResponse({ error: "action_required" }, 400);
  }

  const tripId = body.trip_id as string | undefined;

  if (action !== "create" && !tripId) {
    return jsonResponse({ error: "trip_id_required" }, 400);
  }

  try {
    const service = createServiceClient();

    if (action === "create") {
      return await handleCreate(supabase, user.id, body);
    }
    if (action === "update") {
      return await handleUpdate(supabase, user.id, tripId!, body);
    }
    if (action === "apply") {
      return await handleApply(supabase, service, user.id, tripId!);
    }
    if (action === "decide") {
      const applicantId = body.applicant_id as string | undefined;
      if (!applicantId || body.approved === undefined) {
        return jsonResponse({ error: "applicant_id_and_approved_required" }, 400);
      }
      return await handleDecide(
        supabase,
        service,
        user.id,
        tripId!,
        applicantId,
        !!body.approved,
      );
    }
    if (action === "cancel") {
      return await handleCancel(supabase, user.id, tripId!);
    }
    if (action === "close") {
      return await handleStatusChange(supabase, user.id, tripId!, "closed");
    }
    if (action === "complete") {
      return await handleStatusChange(supabase, user.id, tripId!, "completed");
    }
    if (action === "leave") {
      return await handleLeave(supabase, user.id, tripId!);
    }
    return jsonResponse({ error: "unknown_action" }, 400);
  } catch (e) {
    console.error("trip-actions:", e);
    const msg = e instanceof Error ? e.message : "internal_error";
    if (msg === "trip_full") {
      return jsonResponse({ error: "trip_full", message: "Група вже набрана" }, 409);
    }
    if (msg === "forbidden") {
      return jsonResponse({ error: "forbidden" }, 403);
    }
    if (msg === "trip_not_open") {
      return jsonResponse({ error: "trip_not_open" }, 400);
    }
    if (msg === "already_applied") {
      return jsonResponse({ error: "already_applied" }, 409);
    }
    if (msg === "invalid_dates") {
      return jsonResponse({ error: "invalid_dates" }, 400);
    }
    if (msg === "title_required") {
      return jsonResponse({ error: "title_required" }, 400);
    }
    return jsonResponse({ error: "trip_action_failed", message: msg }, 500);
  }
});

async function insertNotification(
  service: ReturnType<typeof createClient>,
  row: Record<string, unknown>,
): Promise<void> {
  const { error } = await service.from("notifications").insert(row);
  if (error) {
    console.error("notification insert failed:", error);
    throw error;
  }
}

async function handleCreate(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  body: Record<string, unknown>,
): Promise<Response> {
  const title = String(body.title ?? "").trim();
  if (!title) throw new Error("title_required");

  const startDate = String(body.start_date ?? "");
  const endDate = String(body.end_date ?? "");
  if (!startDate || !endDate || startDate > endDate) {
    throw new Error("invalid_dates");
  }

  const maxMembers = Number(body.max_members ?? 10);
  if (!Number.isFinite(maxMembers) || maxMembers < 1) {
    throw new Error("invalid_max_members");
  }

  const routeId = body.route_id as string | null | undefined;

  const { data: inserted, error } = await supabase
    .from("trips")
    .insert({
      title,
      description: String(body.description ?? "").trim(),
      meeting_point: String(body.meeting_point ?? "").trim(),
      max_members: maxMembers,
      start_date: startDate,
      end_date: endDate,
      route_id: routeId || null,
      organizer_id: userId,
      status: "open",
      trip_code: generateTripCode(),
    })
    .select("id, trip_code")
    .single();

  if (error) throw error;

  return jsonResponse({
    ok: true,
    trip_id: inserted.id,
    trip_code: inserted.trip_code,
    status: "open",
  });
}

async function handleUpdate(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  tripId: string,
  body: Record<string, unknown>,
): Promise<Response> {
  const { data: trip, error } = await supabase
    .from("trips")
    .select("organizer_id, status")
    .eq("id", tripId)
    .maybeSingle();

  if (error || !trip) throw new Error("trip_not_found");
  if (trip.organizer_id !== userId) throw new Error("forbidden");
  if (trip.status === "cancelled" || trip.status === "completed") {
    throw new Error("trip_not_editable");
  }

  const startDate = String(body.start_date ?? "");
  const endDate = String(body.end_date ?? "");
  if (!startDate || !endDate || startDate > endDate) {
    throw new Error("invalid_dates");
  }

  const payload = {
    title: String(body.title ?? "").trim(),
    description: String(body.description ?? "").trim(),
    meeting_point: String(body.meeting_point ?? "").trim(),
    max_members: Number(body.max_members ?? 10),
    start_date: startDate,
    end_date: endDate,
    route_id: (body.route_id as string | null) || null,
  };

  if (!payload.title) throw new Error("title_required");

  const { error: updErr } = await supabase
    .from("trips")
    .update(payload)
    .eq("id", tripId);
  if (updErr) throw updErr;

  return jsonResponse({ ok: true, trip_id: tripId });
}

async function handleStatusChange(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  tripId: string,
  status: string,
): Promise<Response> {
  const { data: trip, error } = await supabase
    .from("trips")
    .select("organizer_id")
    .eq("id", tripId)
    .maybeSingle();

  if (error || !trip) throw new Error("trip_not_found");
  if (trip.organizer_id !== userId) throw new Error("forbidden");

  const { error: updErr } = await supabase
    .from("trips")
    .update({ status })
    .eq("id", tripId);
  if (updErr) throw updErr;

  return jsonResponse({ ok: true, status });
}

async function handleLeave(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  tripId: string,
): Promise<Response> {
  const { data: trip, error } = await supabase
    .from("trips")
    .select("organizer_id")
    .eq("id", tripId)
    .maybeSingle();

  if (error || !trip) throw new Error("trip_not_found");
  if (trip.organizer_id === userId) {
    throw new Error("organizer_cannot_leave");
  }

  const { error: delErr } = await supabase
    .from("trip_participants")
    .delete()
    .eq("trip_id", tripId)
    .eq("user_id", userId);
  if (delErr) throw delErr;

  return jsonResponse({ ok: true, status: "left" });
}

async function handleApply(
  supabase: ReturnType<typeof createClient>,
  service: ReturnType<typeof createClient>,
  userId: string,
  tripId: string,
): Promise<Response> {
  const { data: trip, error } = await supabase
    .from("trips")
    .select("id, title, start_date, end_date, status, organizer_id, max_members")
    .eq("id", tripId)
    .maybeSingle();

  if (error || !trip) throw new Error("trip_not_found");
  if (trip.organizer_id === userId) {
    throw new Error("organizer_cannot_apply");
  }
  if (trip.status !== "open") throw new Error("trip_not_open");

  const { data: existing } = await supabase
    .from("trip_participants")
    .select("status")
    .eq("trip_id", tripId)
    .eq("user_id", userId)
    .maybeSingle();

  if (existing?.status === "pending") throw new Error("already_applied");
  if (existing?.status === "approved") throw new Error("already_member");

  const { data: parts } = await supabase
    .from("trip_participants")
    .select("status")
    .eq("trip_id", tripId);
  const approvedN = (parts ?? []).filter((p) => p.status === "approved").length;
  const maxM = (trip.max_members as number) ?? 0;
  if (maxM > 0 && approvedN >= maxM) throw new Error("trip_full");

  const { error: upsertError } = await supabase.from("trip_participants").upsert({
    trip_id: tripId,
    user_id: userId,
    status: "pending",
  });
  if (upsertError) throw upsertError;

  const { data: me } = await supabase
    .from("profiles")
    .select("full_name, age, fitness_level, bio")
    .eq("id", userId)
    .maybeSingle();

  const name = (me?.full_name as string)?.trim() || "Учасник";
  const tripTitle = (trip.title as string)?.trim() || "Похід";
  const dates = formatDates(trip);
  const age = me?.age;
  const fit = fitnessUa[(me?.fitness_level as string) ?? ""] ??
    (me?.fitness_level as string) ?? "—";
  let bio = (me?.bio as string)?.trim() ?? "";
  if (bio.length > 120) bio = `${bio.slice(0, 120)}…`;

  const detailLines = [
    `Похід: ${tripTitle}`,
    ...(dates ? [`Дати: ${dates}`] : []),
    ...(age != null ? [`Вік: ${age}`] : []),
    `Рівень: ${fit}`,
    ...(bio ? [`Про себе: ${bio}`] : []),
  ];

  await insertNotification(service, {
    user_id: trip.organizer_id,
    type: "trip_request",
    title: `Заявка від ${name}`,
    body: detailLines.join("\n"),
    payload: {
      trip_id: tripId,
      applicant_id: userId,
      applicant_name: name,
      trip_title: tripTitle,
    },
  });

  return jsonResponse({ ok: true, status: "pending" });
}

async function handleDecide(
  supabase: ReturnType<typeof createClient>,
  service: ReturnType<typeof createClient>,
  organizerId: string,
  tripId: string,
  applicantId: string,
  approved: boolean,
): Promise<Response> {
  const { data: trip, error } = await supabase
    .from("trips")
    .select("id, title, organizer_id, max_members")
    .eq("id", tripId)
    .maybeSingle();

  if (error || !trip) throw new Error("trip_not_found");
  if (trip.organizer_id !== organizerId) throw new Error("forbidden");

  if (approved) {
    const maxM = (trip.max_members as number) ?? 0;
    const { data: parts } = await supabase
      .from("trip_participants")
      .select("status")
      .eq("trip_id", tripId);
    const approvedN = (parts ?? []).filter((p) => p.status === "approved").length;
    if (maxM > 0 && approvedN >= maxM) throw new Error("trip_full");
  }

  const status = approved ? "approved" : "rejected";
  const { error: updateError } = await supabase
    .from("trip_participants")
    .update({ status })
    .eq("trip_id", tripId)
    .eq("user_id", applicantId);
  if (updateError) throw updateError;

  const tripTitle = (trip.title as string)?.trim() || "Похід";
  const { data: orgProf } = await supabase
    .from("profiles")
    .select("full_name")
    .eq("id", organizerId)
    .maybeSingle();
  const organizerLabel = (orgProf?.full_name as string)?.trim() || "Організатор";

  await insertNotification(service, {
    user_id: applicantId,
    type: approved ? "trip_approved" : "trip_rejected",
    title: approved
      ? `Вас схвалено: ${tripTitle}`
      : `Заявку відхилено: ${tripTitle}`,
    body: approved
      ? `Організатор ${organizerLabel} додав вас до походу «${tripTitle}». Відкрийте чат групи.`
      : `Організатор ${organizerLabel} відхилив запит на похід «${tripTitle}».`,
    payload: {
      trip_id: tripId,
      organizer_name: organizerLabel,
      trip_title: tripTitle,
    },
  });

  return jsonResponse({ ok: true, status });
}

async function handleCancel(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  tripId: string,
): Promise<Response> {
  const { data: trip, error } = await supabase
    .from("trips")
    .select("organizer_id")
    .eq("id", tripId)
    .maybeSingle();

  if (error || !trip) throw new Error("trip_not_found");
  if (trip.organizer_id !== userId) throw new Error("forbidden");

  const { error: updateError } = await supabase
    .from("trips")
    .update({ status: "cancelled" })
    .eq("id", tripId);
  if (updateError) throw updateError;

  return jsonResponse({ ok: true, status: "cancelled" });
}
