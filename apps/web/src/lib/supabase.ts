import { createClient } from "@supabase/supabase-js";
import { SUPABASE_KEY, SUPABASE_URL } from "./data";

// The publishable key only: what a visitor or a staff member may do is decided by row level security in the database.
export const supabase = createClient(SUPABASE_URL || "http://localhost", SUPABASE_KEY || "missing", {
  auth: { persistSession: true, storageKey: "northgate-portal" },
});
