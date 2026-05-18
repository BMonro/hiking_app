// deploy: npx supabase functions deploy trip-actions
// actions: apply | decide | cancel

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { createServiceClient } from "../_shared/auth.ts";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

type Action = "apply" | "decide" | "cancel";

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

  let body: {
    action?: Action;
    trip_id?: string;
    applicant_id?: string;
    approved?: boolean;
  };
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
    const service = createServiceClient();

    if (action === "apply") {
      return await handleApply(supabase, service, user.id, tripId);
    }
    if (action === "decide") {
      const applicantId = body.applicant_id;
      if (!applicantId || body.approved === undefined) {
        return jsonResponse({ error: "applicant_id_and_approved_required" }, 400);
      }
      return await handleDecide(
        supabase,
        service,
        user.id,
        tripId,
        applicantId,
        !!body.approved,
      );
    }
    if (action === "cancel") {
      return await handleCancel(supabase, user.id, tripId);
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
