-- Sprint 5: Advisor review requires a distinct state for a request that is
-- awaiting revised information. Request identity/evidence remain immutable;
-- only secured, versioned lifecycle RPCs may update the state projection.
alter type public.verification_request_status
  add value if not exists 'more_information_required';
