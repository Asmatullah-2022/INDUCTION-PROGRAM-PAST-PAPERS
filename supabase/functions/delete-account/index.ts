// Supabase Edge Function: delete-account
//
// Deletes the CALLING user's own account and their application data
// (bookmarks, practice attempts/answers, progress, profile), then deletes
// the auth.users row. Runs with the service-role key server-side only —
// this key must never be shipped in the Flutter app. The function reads
// the caller's identity from their own JWT, so a user can only ever
// delete their own account.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

Deno.serve(async (req) => {
  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing Authorization header" }), {
        status: 401,
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // Client scoped to the caller's own JWT, used only to identify who is
    // asking — never to perform the privileged delete itself.
    const callerClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await callerClient.auth.getUser();
    if (userError || !userData?.user) {
      return new Response(JSON.stringify({ error: "Invalid session" }), { status: 401 });
    }
    const userId = userData.user.id;

    // Privileged client for the actual deletion, never exposed to any client app.
    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    await adminClient.from("practice_answers").delete().in(
      "attempt_id",
      (await adminClient.from("practice_attempts").select("id").eq("user_id", userId)).data?.map(
        (a: { id: string }) => a.id,
      ) ?? [],
    );
    await adminClient.from("practice_attempts").delete().eq("user_id", userId);
    await adminClient.from("bookmarks").delete().eq("user_id", userId);
    await adminClient.from("user_progress").delete().eq("user_id", userId);
    await adminClient.from("profiles").delete().eq("id", userId);

    const { error: deleteUserError } = await adminClient.auth.admin.deleteUser(userId);
    if (deleteUserError) {
      return new Response(JSON.stringify({ error: deleteUserError.message }), { status: 500 });
    }

    return new Response(JSON.stringify({ success: true }), { status: 200 });
  } catch (error) {
    return new Response(JSON.stringify({ error: (error as Error).message }), { status: 500 });
  }
});
