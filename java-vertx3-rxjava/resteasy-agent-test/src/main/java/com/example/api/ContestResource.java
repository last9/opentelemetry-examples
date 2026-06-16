package com.example.api;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import javax.ws.rs.*;
import javax.ws.rs.core.MediaType;
import javax.ws.rs.core.Response;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionStage;

/**
 * JAX-RS resource that exercises the three FDE-196 fixes in vertx3-otel-agent.
 *
 * Endpoints:
 *
 *   GET  /api/v1/contests/{id}           — url.query test (Bug 3)
 *   POST /api/v1/contests/{id}/submit    — body capture + async CompletionStage (Bug 1 + 2)
 *   POST /api/v1/contests/{id}/fail      — async exception via writeException (Bug 2)
 *   POST /api/v1/contests/{id}/fail-sync — synchronous exception (baseline, always worked)
 */
@Path("/api/v1/contests")
@Produces(MediaType.APPLICATION_JSON)
public class ContestResource {

    private static final Logger log = LoggerFactory.getLogger(ContestResource.class);

    // ---- Bug 3: url.query ----

    /**
     * GET /api/v1/contests/{id}?wsId=123&tournamentId=456
     *
     * Verify on span: url.query = "wsId=123&tournamentId=456"
     */
    @GET
    @Path("/{id}")
    public Response getContest(@PathParam("id") String id,
                               @QueryParam("wsId") String wsId,
                               @QueryParam("tournamentId") String tournamentId) {
        log.info("getContest id={} wsId={} tournamentId={}", id, wsId, tournamentId);
        return Response.ok(
                "{\"contestId\":\"" + id + "\",\"wsId\":\"" + wsId + "\"}"
        ).build();
    }

    // ---- Bug 1 + 2: body capture + async CompletionStage success ----

    /**
     * POST /api/v1/contests/{id}/submit
     * Content-Type: application/json
     * Body: {"teamId":"t1","wsId":123}
     *
     * Verify on span with VERTX_OTEL_BODY_CAPTURE_ENABLED=true:
     *   http.request.body = {"teamId":"t1","wsId":123}
     *
     * With VERTX_OTEL_BODY_CAPTURE_ERROR_ONLY=true: body appears only on 4xx/5xx.
     */
    @POST
    @Path("/{id}/submit")
    @Consumes(MediaType.APPLICATION_JSON)
    public CompletionStage<Response> submitTeam(@PathParam("id") String id, String body) {
        log.info("submitTeam id={} body={}", id, body);
        return CompletableFuture.supplyAsync(() ->
                Response.ok("{\"status\":\"ok\",\"contestId\":\"" + id + "\"}").build()
        );
    }

    // ---- Bug 2: async exception → writeException → exception event on span ----

    /**
     * POST /api/v1/contests/{id}/fail
     * Content-Type: application/json
     * Body: {"teamId":"t1"}
     *
     * Simulates a failed CompletionStage (equivalent to RxJava onErrorResumeNext throwing).
     * RESTEasy calls SynchronousDispatcher.writeException() instead of propagating the
     * exception through invoke() — so @Advice.Thrown is null without the FDE-196 fix.
     *
     * Verify on span:
     *   status = ERROR
     *   exception event with message "simulated team submission failure"
     *   http.request.body = {"teamId":"t1"}  (with VERTX_OTEL_BODY_CAPTURE_ENABLED=true)
     */
    @POST
    @Path("/{id}/fail")
    @Consumes(MediaType.APPLICATION_JSON)
    public CompletionStage<Response> failAsync(@PathParam("id") String id, String body) {
        log.info("failAsync id={} body={}", id, body);
        CompletableFuture<Response> future = new CompletableFuture<>();
        future.completeExceptionally(
                new RuntimeException("simulated team submission failure for contest " + id)
        );
        return future;
    }

    // ---- Baseline: synchronous 5xx (always worked) ----

    /**
     * POST /api/v1/contests/{id}/fail-sync
     *
     * Synchronous exception — @Advice.Thrown picks this up even without FDE-196.
     * Use as a baseline to confirm the agent is working at all.
     */
    @POST
    @Path("/{id}/fail-sync")
    @Consumes(MediaType.APPLICATION_JSON)
    public Response failSync(@PathParam("id") String id, String body) {
        throw new WebApplicationException("sync error for contest " + id,
                Response.Status.INTERNAL_SERVER_ERROR);
    }
}
