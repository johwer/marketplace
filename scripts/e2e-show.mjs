#!/usr/bin/env node
/**
 * e2e-show.mjs — Run passing E2E tests in headed/UI mode, skip failing ones.
 *
 * Usage:
 *   node ~/.claude/scripts/e2e-show.mjs           # headed (default)
 *   node ~/.claude/scripts/e2e-show.mjs --ui      # Playwright UI mode
 *   node ~/.claude/scripts/e2e-show.mjs --refresh # force re-probe
 *
 * Flow:
 *   1. Locate apps/web/ by walking up from cwd
 *   2. Run headless probe (or load cache < 5 min old)
 *   3. Skip failing tests via --grep-invert
 *   4. Run in headed/UI mode with Vite proxy noise filtered from output
 */

import { spawnSync, spawn } from "child_process";
import { writeFileSync, readFileSync, existsSync } from "fs";
import { resolve, join, dirname } from "path";
import { homedir } from "os";
import { Transform } from "stream";

const CACHE_FILE_NAME = ".playwright-show-cache.json";
const CACHE_MAX_AGE_MS = 5 * 60 * 1000;

// Vite proxy noise — harmless but floods the terminal
const NOISE_RE = /ECONNREFUSED|http proxy error|AggregateError|internalConnectMultiple|afterConnectMultiple|ExperimentalWarning.*ES Module/;

const args = process.argv.slice(2);
const forceRefresh = args.includes("--refresh");
const mode = args.find((a) => a.startsWith("--") && a !== "--refresh") ?? "--headed";

const log = (msg) => process.stdout.write(msg + "\n");

// ── Find apps/web ─────────────────────────────────────────────────────────

function findWebDir() {
    if (existsSync(join(process.cwd(), "playwright.config.ts"))) return process.cwd();

    let dir = process.cwd();
    while (true) {
        const candidate = join(dir, "apps", "web", "playwright.config.ts");
        if (existsSync(candidate)) return join(dir, "apps", "web");
        const parent = dirname(dir);
        if (parent === dir) break;
        dir = parent;
    }

    const dtfConfig = join(homedir(), ".claude", "dtf-config.json");
    if (existsSync(dtfConfig)) {
        try {
            const cfg = JSON.parse(readFileSync(dtfConfig, "utf-8"));
            const candidate = join(cfg.monorepoPath ?? "", "apps", "web");
            if (existsSync(join(candidate, "playwright.config.ts"))) return candidate;
        } catch { /* ignore */ }
    }

    return null;
}

const webDir = findWebDir();
if (!webDir) {
    log("❌ Could not find apps/web/playwright.config.ts — run from within the monorepo.");
    process.exit(1);
}

log(`📁 ${webDir}`);
process.chdir(webDir);

// ── Cache ─────────────────────────────────────────────────────────────────

const CACHE_FILE = resolve(CACHE_FILE_NAME);

function loadCache() {
    if (forceRefresh || !existsSync(CACHE_FILE)) return null;
    try {
        const cache = JSON.parse(readFileSync(CACHE_FILE, "utf-8"));
        if (Date.now() - cache.ts > CACHE_MAX_AGE_MS) return null;
        const age = Math.round((Date.now() - cache.ts) / 1000);
        log(`📦 Cached probe (${age}s ago) — pass --refresh to re-probe`);
        return cache;
    } catch { return null; }
}

function saveCache(failures) {
    writeFileSync(CACHE_FILE, JSON.stringify({ ts: Date.now(), failures }, null, 2));
}

// ── JSON result parser ────────────────────────────────────────────────────

function collectFailures(suite) {
    const failures = [];
    for (const spec of suite.specs ?? []) {
        const failed = spec.tests?.some((t) =>
            t.results?.some((r) => ["failed", "timedOut"].includes(r.status))
        );
        if (failed) failures.push(spec.title);
    }
    for (const sub of suite.suites ?? []) failures.push(...collectFailures(sub));
    return failures;
}

// ── Probe (headless, JSON reporter, no noise filter needed) ───────────────

function probe() {
    log("🔍 Probing headlessly to find failures…\n");
    const result = spawnSync("npx", ["playwright", "test", "--reporter=json"], {
        encoding: "utf-8",
        stdio: ["inherit", "pipe", "inherit"],
        env: { ...process.env },
        cwd: webDir,
    });

    try {
        const parsed = JSON.parse(result.stdout);
        return (parsed.suites ?? []).flatMap(collectFailures);
    } catch {
        log("\n⚠️  Could not parse probe output — running all tests");
        return null;
    }
}

// ── Noise-filtered spawn ──────────────────────────────────────────────────

function runWithNoiseFilter(playwrightArgs) {
    return new Promise((resolve) => {
        const proc = spawn("npx", playwrightArgs, {
            stdio: ["inherit", "pipe", "pipe"],
            cwd: webDir,
            env: { ...process.env },
        });

        // Filter noise from both stdout and stderr, forward the rest
        function makeFilter(dest) {
            return new Transform({
                transform(chunk, _enc, cb) {
                    const lines = chunk.toString().split("\n");
                    const kept = lines.filter((l) => !NOISE_RE.test(l));
                    if (kept.length > 0) dest.write(kept.join("\n"));
                    cb();
                },
            });
        }

        proc.stdout.pipe(makeFilter(process.stdout));
        proc.stderr.pipe(makeFilter(process.stderr));

        proc.on("close", (code) => resolve(code ?? 0));
    });
}

// ── Main ──────────────────────────────────────────────────────────────────

const cached = loadCache();
const failures = cached?.failures ?? probe();

if (failures === null) {
    const r = spawnSync("npx", ["playwright", "test", mode], { stdio: "inherit", cwd: webDir });
    process.exit(r.status ?? 0);
}

saveCache(failures);
log("");

const runArgs = ["playwright", "test", mode];

if (failures.length === 0) {
    log(`✅ All tests pass — running in ${mode} mode\n`);
} else {
    log(`⏭️  Skipping ${failures.length} failing test(s):`);
    failures.forEach((f) => log(`   • ${f}`));
    log("");
    const pattern = failures.map((f) => f.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|");
    runArgs.push("--grep-invert", pattern);
    log(`▶  Running passing tests in ${mode} mode…\n`);
}

const exitCode = await runWithNoiseFilter(runArgs);
process.exit(exitCode);
