import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import path from "node:path";
import os from "node:os";

// Directories that are never touched without confirmation.
// Container context: relevant in case the user explicitly mounts host
// paths (e.g. ~/.ssh) into the image.
const PROTECTED_DIRS = [
  path.join(os.homedir(), ".ssh"),
  path.join(os.homedir(), ".aws"),
  path.join(os.homedir(), ".config/gcloud"),
  "/run/secrets",
  "/etc",
];

// Patterns that may appear in filenames or commands - but only after confirmation.
const PROTECTED_PATTERNS: RegExp[] = [
  /\.env(\.|$)/,
  /credentials\.json$/,
  /id_rsa(\.|$)/,
  /id_ed25519(\.|$)/,
  /\.pem$/,
  /\.p12$/,
];

const FILE_TOOLS = new Set(["read", "write", "edit"]);

function extractPathFromInput(input: unknown): string | null {
  if (typeof input !== "object" || input === null) return null;
  const obj = input as Record<string, unknown>;
  const candidate = obj.path ?? obj.file_path ?? obj.filename;
  return typeof candidate === "string" ? candidate : null;
}

function isProtectedPath(target: string): { hit: boolean; reason: string } {
  const resolved = path.resolve(target);
  for (const dir of PROTECTED_DIRS) {
    if (resolved === dir || resolved.startsWith(dir + path.sep)) {
      return { hit: true, reason: `Directory ${dir}` };
    }
  }
  for (const pattern of PROTECTED_PATTERNS) {
    if (pattern.test(resolved)) {
      return { hit: true, reason: `Pattern ${pattern.source}` };
    }
  }
  return { hit: false, reason: "" };
}

function bashTouchesProtectedPattern(command: string): {
  hit: boolean;
  reason: string;
} {
  for (const pattern of PROTECTED_PATTERNS) {
    if (pattern.test(command)) {
      return { hit: true, reason: `Pattern ${pattern.source} in command` };
    }
  }
  for (const dir of PROTECTED_DIRS) {
    if (command.includes(dir)) {
      return { hit: true, reason: `Reference to ${dir}` };
    }
  }
  return { hit: false, reason: "" };
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    const { toolName: name, input } = event;

    if (FILE_TOOLS.has(name)) {
      const target = extractPathFromInput(input);
      if (!target) return;

      const check = isProtectedPath(target);
      if (!check.hit) return;

      const ok = await ctx.ui.confirm(
        "Protected path",
        `Tool "${name}" -> "${target}"\nReason: ${check.reason}\nAllow?`,
      );
      if (!ok) {
        throw new Error(
          `[protected-paths] Access to ${target} denied (${check.reason})`,
        );
      }
    }

    if (name === "bash") {
      const command =
        typeof (input as { command?: unknown }).command === "string"
          ? (input as { command: string }).command
          : "";
      if (!command) return;

      const check = bashTouchesProtectedPattern(command);
      if (!check.hit) return;

      const ok = await ctx.ui.confirm(
        "Protected pattern in bash command",
        `Command: ${command.slice(0, 200)}${command.length > 200 ? "..." : ""}\nReason: ${check.reason}\nAllow?`,
      );
      if (!ok) {
        throw new Error(
          `[protected-paths] Bash command denied (${check.reason})`,
        );
      }
    }
  });

  ctx_log(
    `[protected-paths] active - ${PROTECTED_DIRS.length} dirs, ${PROTECTED_PATTERNS.length} patterns`,
  );
}

function ctx_log(msg: string) {
  // eslint-disable-next-line no-console
  console.error(msg);
}
