import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export async function canAccessTripChat(
  supabase: SupabaseClient,
  userId: string,
  tripId: string,
): Promise<boolean> {
  const { data: trip, error } = await supabase
    .from("trips")
    .select("organizer_id, status")
    .eq("id", tripId)
    .maybeSingle();

  if (error || !trip) return false;
  if (trip.status === "cancelled") return false;
  if (trip.organizer_id === userId) return true;

  const { data: part } = await supabase
    .from("trip_participants")
    .select("status")
    .eq("trip_id", tripId)
    .eq("user_id", userId)
    .maybeSingle();

  return part?.status === "approved";
}
