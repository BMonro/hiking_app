

DROP POLICY IF EXISTS "notifications_insert_trip_request_to_organizer" ON notifications;
DROP POLICY IF EXISTS "notifications_insert_trip_decision_to_applicant" ON notifications;

CREATE POLICY "notifications_insert_trip_request_to_organizer"
  ON notifications
  FOR INSERT
  TO authenticated
  WITH CHECK (
    type = 'trip_request'
    AND (payload->>'applicant_id')::uuid = auth.uid()
    AND EXISTS (
      SELECT 1
      FROM trips t
      WHERE t.id = (payload->>'trip_id')::uuid
        AND t.organizer_id = user_id
    )
  );

CREATE POLICY "notifications_insert_trip_decision_to_applicant"
  ON notifications
  FOR INSERT
  TO authenticated
  WITH CHECK (
    type IN ('trip_approved', 'trip_rejected')
    AND EXISTS (
      SELECT 1
      FROM trips t
      WHERE t.id = (payload->>'trip_id')::uuid
        AND t.organizer_id = auth.uid()
    )
    AND EXISTS (
      SELECT 1
      FROM trip_participants tp
      WHERE tp.trip_id = (payload->>'trip_id')::uuid
        AND tp.user_id = user_id
    )
  );
