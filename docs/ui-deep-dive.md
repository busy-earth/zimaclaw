# Zimaclaw UI Layer: Svelte vs. LangGraph Deep Agent

> **Status note (2026-04-01):** This is a forward-looking UI design doc. The current shipped Molt slice does not include UI/SSE streaming yet; treat this file as implementation guidance for deferred work listed in `README.md`.

## Executive Summary

Building a Tailscale-accessible dashboard for Zimaclaw that visualizes XMPP message ingress and parallel Pi subagent streams is straightforward with plain SvelteKit — and that is the better choice. The LangGraph `deepagent` example is instructive as a UI *pattern* but requires the LangGraph Server runtime as a hard backend dependency; grafting it onto Zimaclaw would mean replacing Zig with a Node.js/Python orchestrator or building a shim layer, which defeats the purpose. A custom SvelteKit 5 app with Server-Sent Events (SSE) from httpz and Tailscale Serve for TLS is the clean, lightweight, reproducible path.

***

## Why the LangGraph Example Is a Pattern, Not a Library

The `deepagent` UI in `langchain-ai/langgraphjs/examples/ui-react` is genuinely well-designed for the parallel-card pattern. Its `SubagentCard.tsx` tracks a `SubagentStream` object with `status` (`pending | running | complete | error`), `messages`, `startedAt`, `completedAt`, and a `result` field — exactly the shape you'd want. The `SubagentPipeline.tsx` renders cards in a responsive grid and `index.tsx` maps human-message turns to their corresponding subagent activations.

However, none of that component logic is standalone. The entire state model flows from `useStream()` from `@langchain/langgraph-sdk/react`, which makes HTTP calls to the **LangGraph Server** running at `http://localhost:2024`. `useStream()` calls `stream.subagents`, `stream.getSubagentsByMessage()`, and `filterSubagentMessages` — all implemented inside the SDK against the LangGraph Server protocol, not a generic SSE endpoint. The `assistantId` and thread management APIs are LangGraph-proprietary. Running this against Zimaclaw would require either:[^1][^2]

1. Embedding a full LangGraph Server (Python or Node) in front of Zig as a proxy, or
2. Implementing the LangGraph Server API surface in Zig — a substantial reverse-engineering effort

Additionally, the LangGraph dev server requires a `LANGSMITH_API_KEY` and historically has had 2-minute rebuild cycles, which conflicts with Zimaclaw's reproducible NixOS flake model. The right move is to **steal the visual patterns** from `SubagentCard.tsx` and `SubagentPipeline.tsx` and reimplement them in Svelte against a purpose-built SSE event schema.[^3][^4]

***

## Svelte 5 Is the Right Tool Here

### Framework Fit

Svelte 5's `$state` rune with fine-grained reactivity is purpose-built for exactly this workload: many small, independent state objects (one per Pi worker) receiving high-frequency streaming updates. At 47KB bundle vs React's 156KB, it aligns with a headless appliance that doesn't need a heavyweight runtime. Real-world usage on streaming log dashboards (similar pattern) confirms that Svelte 5 with SSE and `$state` handles 50–100 events/second per stream without unnecessary re-renders.[^5][^6]

Svelte compiles to vanilla JS with no framework runtime in the browser. For a private Tailscale-only dashboard, this means fast initial load even on a headless NixOS box that may have marginal memory pressure from running Pi workers and the Emacs daemon simultaneously.[^7]

### SvelteKit Deployment on NixOS

SvelteKit with `adapter-node` produces a standalone Node.js server (`build/index.js`) that can be declared as a systemd service in the NixOS flake. Set `HOST=127.0.0.1` and `PORT=8080`, then let Tailscale Serve proxy it. No Docker, no Vercel, no cloud dependencies. The entire frontend becomes a flake input pinned to a specific commit, fully reproducible alongside the Zig binary.[^8]

Alternatively, if you want zero Node.js at runtime, use `adapter-static` to build a pure SPA. In this case, all the SSE connection logic lives in the browser, and the Zig binary serves static assets plus the SSE endpoints from httpz — no Node process required at all.[^9]

***

## The SSE Transport Layer from Zig

`http.zig` (karlseguin/http.zig) supports Server-Sent Events natively via `res.startEventStream(context, handler_fn)`. The handler receives an `std.net.Stream` and runs in its own thread, writing raw SSE frames:

```
event: xmpp_message\n
data: {"from":"user@xmpp.example","body":"fix the login bug"}\n\n

event: subagent_start\n
data: {"id":"pi-worker-2","task":"add OAuth handler","status":"running"}\n\n

event: subagent_chunk\n
data: {"id":"pi-worker-2","delta":"Creating src/auth.ts..."}\n\n

event: subagent_done\n
data: {"id":"pi-worker-2","status":"complete","elapsed_ms":14320}\n\n
```

This SSE endpoint is the **only backend contract** between Zig and Svelte. The UI subscribes with a browser `EventSource`, and Svelte reactive state handles the rest. httpz also supports WebSockets if you want bidirectional control (e.g., sending new XMPP prompts from the UI back to Zig).

***

## Event Schema Design

The schema that maps cleanly onto the `SubagentCard` visual pattern:

| Event Type | Payload Fields | Triggers |
|---|---|---|
| `xmpp_message` | `from`, `body`, `timestamp`, `msg_id` | New inbound XMPP prompt |
| `subagent_start` | `id`, `task_description`, `triggered_by_msg_id` | Pi worker spawned |
| `subagent_chunk` | `id`, `delta` | JSONL token from Pi stdout |
| `subagent_thinking` | `id`, `reasoning_delta` | Pi reasoning/thinking block (if model emits it) |
| `subagent_tool_call` | `id`, `tool`, `args` | Pi invoking a tool |
| `subagent_done` | `id`, `status`, `result_summary`, `elapsed_ms` | Pi worker exits |
| `emacs_op` | `operation`, `result`, `duration_ms` | emacsclient call log |
| `orchestrator_status` | `workers_active`, `workers_idle`, `queue_depth` | Heartbeat |

This is completely custom to Zimaclaw — no LangGraph Server needed.

***

## Svelte State Model

The Svelte 5 state model is almost a 1:1 translation of what `SubagentCard.tsx` consumes from `SubagentStream`:

```typescript
// stores/subagents.svelte.ts
export class SubagentStore {
  agents = $state<Map<string, SubagentState>>(new Map());

  handleEvent(type: string, data: any) {
    if (type === 'subagent_start') {
      this.agents.set(data.id, {
        id: data.id,
        task: data.task_description,
        status: 'running',
        content: '',
        startedAt: new Date(),
        completedAt: null,
        triggeredBy: data.triggered_by_msg_id,
      });
    } else if (type === 'subagent_chunk') {
      const agent = this.agents.get(data.id);
      if (agent) agent.content += data.delta;
    } else if (type === 'subagent_done') {
      const agent = this.agents.get(data.id);
      if (agent) {
        agent.status = data.status;
        agent.completedAt = new Date();
      }
    }
  }
}
```

The `$state` rune ensures only the specific card whose `content` changed re-renders — no diffing the whole agent map. For thinking/reasoning tokens, add a separate `reasoning` field and render it in a collapsible section within the card (matching the pattern the LangGraph deepagent example implies but doesn't fully implement).[^10][^6]

***

## Tailscale Integration

`tailscale serve` proxies your local SvelteKit Node server (or httpz static file server) through Tailscale's MagicDNS with automatic TLS via Let's Encrypt — no self-signed certs, no browser warnings. The entire setup is a single command:[^11][^12]

```bash
tailscale serve https / http://localhost:8080
```

For the NixOS flake, this becomes a `services.tailscale.enable = true` declaration plus a `systemd.services.zimaclaw-ui` entry. The UI is reachable at `https://nixos-hostname.tailnet-name.ts.net` from any device on your tailnet — your dev machine, phone, tablet — with zero public internet exposure.[^12][^11]

***

## Decision Matrix

| Concern | Custom Svelte + httpz SSE | LangGraph deepagent (adapted) |
|---|---|---|
| Backend dependency | httpz (already in Zig binary) | LangGraph Server (Node/Python)[^1] |
| Reproducibility in Nix flake | Full — pinned npm lockfile + adapter-node[^13] | Partial — requires LangGraph Server in flake |
| Subagent card pattern | Reimplemented (1–2 days) | Already built |
| XMPP message timeline | Custom (straightforward) | Not present in deepagent |
| Thinking/reasoning display | Custom | Partially present |
| Bundle size | ~47KB Svelte 5[^5] | ~156KB React 19[^5] |
| SSE reconnect on page refresh | `EventSource` auto-reconnects natively | `reconnectOnMount: true` via SDK |
| Vendor lock-in | None | LangGraph SDK + Server protocol[^1] |
| Dev iteration speed | Fast (Vite HMR) | Slow (2-min Docker rebuilds)[^3] |

***

## Recommended Architecture

1. **Zig (httpz)** exposes two endpoints:
   - `GET /events` — SSE stream with the event schema above, one persistent connection per browser client
   - `GET /static/*` — serves the compiled SvelteKit SPA (`adapter-static`) or proxies to the SvelteKit Node server

2. **SvelteKit 5 SPA** subscribes to `/events` via `EventSource`, maintains reactive state per subagent and XMPP message, renders the parallel card grid modeled on `SubagentPipeline.tsx`/`SubagentCard.tsx` visual patterns

3. **Tailscale Serve** terminates TLS and proxies to httpz on localhost, reachable only on your tailnet[^12]

4. **NixOS flake** declares the SvelteKit build output as a package, the httpz static serving as a systemd service, and `tailscale serve` configuration as a NixOS module

This keeps the entire stack inside the existing Zig binary for production — no Node.js process at runtime if using `adapter-static`. The LangGraph deepagent's component visuals are the right inspiration; its runtime is not.

---

## References

1. [How to integrate LangGraph into your React application - LangChain Docslangchain-5e9cc07a.mintlify.app › langsmith › use-stream-react](https://langchain-5e9cc07a.mintlify.app/langsmith/use-stream-react)

2. [How to integrate LangGraph into your React application¶](https://langchain-ai.github.io/langgraph/cloud/how-tos/use_stream_react/) - Build reliable, stateful AI systems, without giving up control

3. [How to improve iteration speed with dev server? - LangGraph](https://forum.langchain.com/t/how-to-improve-iteration-speed-with-dev-server/283) - A few workarounds: mount your source code as a volume in the dev server's Docker container so change...

4. [langgraph up broken again.. · Issue #1456 · langchain-ai ... - GitHub](https://github.com/langchain-ai/langgraph/issues/1456) - Checked other resources I added a very descriptive title to this issue. I searched the LangGraph/Lan...

5. [Svelte 5 vs React 19 vs Vue 4: The 2025 Framework War Nobody ...](https://jsgurujobs.com/blog/svelte-5-vs-react-19-vs-vue-4-the-2025-framework-war-nobody-expected-performance-benchmarks) - Real benchmark data from identical production apps. Svelte 5 at 47KB, Vue 3 at 89KB, React 19 at 156...

6. [Svelte 5 with Runes: Handling High-Frequency Data](https://www.linkedin.com/posts/gyaansetu-webdev_real-world-svelte-5-handling-high-frequency-activity-7401267090806124545-RI59) - Real-world Svelte 5: Handling high-frequency real-time data with Runes Svelte 5 is officially out, a...

7. [Svelte vs React vs Vue in 2025. Comparing frontend frameworks](https://merge.rocks/blog/comparing-front-end-frameworks-for-startups-in-2025-svelte-vs-react-vs-vue) - Compare React, Vue, and Svelte frontend frameworks for startups in 2025 and choose the best web UI f...

8. [How to deploy SvelteKit on your own server properly without ...](https://stackoverflow.com/questions/78725715/how-to-deploy-sveltekit-on-your-own-server-properly-without-interrupting-the-use) - Before building the app, make sure you've installed adapter-node as per the documentation on your Sv...

9. [Announcing SvelteKit 1.0](https://svelte.dev/blog/announcing-sveltekit-1.0) - Web development, streamlined

10. [$state • Svelte Docs](https://svelte.dev/docs/svelte/$state) - The $state rune allows you to create reactive state, which means that your UI reacts when it changes...

11. [Exposing Local Development Servers Securely with Tailscale Serve](https://peyloride.com/posts/exposing-local-development-servers-securely-with-tailscale-serve/) - Expose local development servers securely with Tailscale Serve — a private, encrypted ngrok alternat...

12. [App Capabilities Header](https://tailscale.com/docs/features/tailscale-serve) - Explore the Tailscale Serve service.

13. [Building your app • SvelteKit Docs](https://svelte.dev/docs/kit/building-your-app) - Building a SvelteKit app happens in two stages, which both happen when you run vite build (usually v...

