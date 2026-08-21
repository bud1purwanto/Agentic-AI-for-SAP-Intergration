import { ImapFlow, type ImapFlowOptions } from "imapflow";
import nodemailer, { type Transporter } from "nodemailer";
import { simpleParser, type ParsedMail } from "mailparser";
import TurndownService from "turndown";

/**
 * Server configuration. Credentials (password) are NEVER hardcoded —
 * they are read exclusively from process.env.EMAIL_PASS.
 *
 * The mail server is Microsoft Exchange Server 2007, which only speaks
 * legacy TLS 1.0 — a protocol that modern Node/OpenSSL has removed. We
 * therefore reach IMAP through a local `stunnel` bridge that terminates the
 * legacy TLS and exposes a plaintext loopback port. SMTP goes directly to the
 * submission port (587), which accepts AUTH LOGIN. Hosts/ports are overridable
 * via env so the deployment can be tuned without code changes.
 */
const env = (key: string, fallback: string): string =>
  process.env[key]?.trim() || fallback;

const envNum = (key: string, fallback: number): number => {
  const v = process.env[key]?.trim();
  const n = v ? Number(v) : NaN;
  return Number.isFinite(n) ? n : fallback;
};
const envBool = (key: string, fallback: boolean): boolean => {
  const v = process.env[key]?.trim().toLowerCase();
  if (v === undefined || v === "") return fallback;
  return v === "true" || v === "1" || v === "yes";
};

// IMAP: by default points at the local stunnel bridge (plaintext loopback).
const IMAP_CONFIG = {
  host: env("IMAP_HOST", "127.0.0.1"),
  port: envNum("IMAP_PORT", 11993),
  secure: envBool("IMAP_SECURE", false),
} as const;

// SMTP: direct to Exchange submission port 587 (465/SMTPS is firewall-blocked).
const SMTP_CONFIG = {
  host: env("SMTP_HOST", "mail.triasmail.co.id"),
  port: envNum("SMTP_PORT", 587),
  secure: envBool("SMTP_SECURE", false),
} as const;

function getPassword(): string {
  const pass = process.env.EMAIL_PASS;
  if (!pass || pass.trim() === "") {
    throw new Error(
      "EMAIL_PASS environment variable is not set. " +
        "Set it (e.g. in a .env file) before starting the server."
    );
  }
  return pass;
}

function getEmailUser(): string {
  const user = process.env.EMAIL_USER?.trim();
  if (!user) {
    throw new Error(
      "EMAIL_USER environment variable is not set. " +
        "Set it (e.g. in a .env file) before starting the server."
    );
  }
  return user;
}

function getLoginUser(): string {
  const user = process.env.EMAIL_LOGIN_USER?.trim();
  if (!user) {
    throw new Error(
      "EMAIL_LOGIN_USER environment variable is not set. " +
        "Set it (e.g. in a .env file) before starting the server."
    );
  }
  return user;
}

export interface EmailSummary {
  messageId: string;
  subject: string;
  from: string;
  date: string;
}

export interface AttachmentInfo {
  filename: string;
  contentType: string;
  size: number;
  isInline: boolean;
}

export interface EmailDetail {
  messageId: string;
  subject: string;
  from: string;
  to: string;
  date: string;
  body: string;
  attachments: AttachmentInfo[];
}

export interface ImageAttachment {
  filename: string;
  mimeType: string;
  base64: string;
}

// Guard against accidentally pulling a huge file into the LLM context.
const MAX_IMAGE_BYTES = 8 * 1024 * 1024; // 8 MB

/**
 * EmailClient holds a single long-lived IMAP connection (instead of opening a
 * new one on every tool call) and a reusable SMTP transport pool.
 *
 * The IMAP connection is lazily created, automatically reconnected if it has
 * dropped, and guarded by a mutex so concurrent tool calls reuse the same
 * connection safely.
 */
export class EmailClient {
  private imap: ImapFlow | null = null;
  private imapReady: Promise<ImapFlow> | null = null;
  private transporter: Transporter | null = null;
  private readonly turndown = new TurndownService({
    headingStyle: "atx",
    codeBlockStyle: "fenced",
  });

  // ---- IMAP ---------------------------------------------------------------

  private buildImapOptions(): ImapFlowOptions {
    return {
      ...IMAP_CONFIG,
      auth: { user: getLoginUser(), pass: getPassword() },
      logger: false,
      // The stunnel bridge already provides TLS to Exchange; the loopback hop
      // is plaintext, so never attempt a (doomed) STARTTLS upgrade on it.
      doSTARTTLS: false,
      // Keep the socket alive so we can reuse it across tool calls.
      socketTimeout: 5 * 60 * 1000,
    };
  }

  /**
   * Returns a connected, usable ImapFlow client, (re)connecting if needed.
   * Concurrent callers share the same in-flight connection promise.
   */
  private async getImap(): Promise<ImapFlow> {
    if (this.imap && this.imap.usable) {
      return this.imap;
    }
    if (this.imapReady) {
      return this.imapReady;
    }

    this.imapReady = (async () => {
      const client = new ImapFlow(this.buildImapOptions());

      client.on("error", (err) => {
        console.error("[IMAP] connection error:", err?.message ?? err);
      });
      client.on("close", () => {
        // Drop the cached client so the next call reconnects.
        if (this.imap === client) {
          this.imap = null;
          this.imapReady = null;
        }
      });

      await client.connect();
      this.imap = client;
      return client;
    })();

    try {
      return await this.imapReady;
    } catch (err) {
      this.imap = null;
      this.imapReady = null;
      throw err;
    }
  }

  /**
   * Search the INBOX and return lightweight summaries.
   */
  async searchEmails(opts: {
    query?: string;
    from?: string;
    maxResults: number;
    unreadOnly: boolean;
  }): Promise<EmailSummary[]> {
    const { query, from, maxResults, unreadOnly } = opts;
    const client = await this.getImap();
    const lock = await client.getMailboxLock("INBOX");
    try {
      // Build IMAP search criteria.
      const criteria: Record<string, unknown> = {};
      if (unreadOnly) criteria.seen = false;
      // Filter by sender using the IMAP FROM header criterion (matches name OR address).
      if (from && from.trim() !== "") {
        criteria.from = from.trim();
      }
      // Filter by keyword in subject OR body text.
      if (query && query.trim() !== "") {
        criteria.or = [{ subject: query }, { body: query }];
      }
      // Empty criteria => match all.
      const searchArg = Object.keys(criteria).length ? criteria : { all: true };

      const uids = await client.search(searchArg, { uid: true });
      if (!uids || uids.length === 0) return [];

      // Newest first, then cap.
      const selected = uids.slice().sort((a, b) => b - a).slice(0, maxResults);

      const results: EmailSummary[] = [];
      for await (const msg of client.fetch(
        selected,
        { uid: true, envelope: true },
        { uid: true }
      )) {
        const env = msg.envelope;
        const fromAddr = env?.from?.[0];
        results.push({
          messageId: env?.messageId ?? `uid:${msg.uid}`,
          subject: env?.subject ?? "(no subject)",
          from: fromAddr
            ? `${fromAddr.name ? fromAddr.name + " " : ""}<${fromAddr.address ?? ""}>`.trim()
            : "(unknown)",
          date: env?.date ? new Date(env.date).toISOString() : "",
        });
      }
      // Preserve newest-first order (fetch may reorder by uid).
      results.sort((a, b) => (a.date < b.date ? 1 : -1));
      return results;
    } finally {
      lock.release();
    }
  }

  /**
   * Resolve a messageId ("uid:<n>" or RFC Message-ID) to an IMAP UID.
   * Caller must hold the mailbox lock.
   */
  private async resolveUid(client: ImapFlow, messageId: string): Promise<number> {
    let uid: number | undefined;

    if (messageId.startsWith("uid:")) {
      uid = Number(messageId.slice(4));
    } else {
      const found = await client.search(
        { header: { "message-id": messageId } },
        { uid: true }
      );
      if (found && found.length) uid = found[found.length - 1];
    }

    if (!uid || Number.isNaN(uid)) {
      throw new Error(`Email with messageId "${messageId}" was not found in INBOX.`);
    }
    return uid;
  }

  /** Fetch and parse the full RFC822 source for a message. Caller holds the lock. */
  private async fetchParsed(client: ImapFlow, uid: number, messageId: string): Promise<ParsedMail> {
    const msg = await client.fetchOne(String(uid), { uid: true, source: true }, { uid: true });
    if (!msg || !msg.source) {
      throw new Error(`Could not fetch source for messageId "${messageId}".`);
    }
    return simpleParser(msg.source);
  }

  /**
   * Fetch one email by its RFC Message-ID (or "uid:<n>" fallback) and return a
   * clean, token-efficient body (HTML converted to Markdown), plus a list of
   * attachments (metadata only — use getImageAttachment() to fetch image bytes).
   */
  async readEmail(messageId: string): Promise<EmailDetail> {
    const client = await this.getImap();
    const lock = await client.getMailboxLock("INBOX");
    try {
      const uid = await this.resolveUid(client, messageId);
      const parsed = await this.fetchParsed(client, uid, messageId);
      const body = this.extractCleanBody(parsed);

      const attachments: AttachmentInfo[] = (parsed.attachments ?? []).map((a) => ({
        filename: a.filename ?? `${a.contentType.replace("/", ".")}`,
        contentType: a.contentType,
        size: a.size ?? a.content.length,
        isInline: a.contentDisposition === "inline" || Boolean(a.cid),
      }));

      return {
        messageId: parsed.messageId ?? messageId,
        subject: parsed.subject ?? "(no subject)",
        from: parsed.from?.text ?? "(unknown)",
        to: parsed.to
          ? Array.isArray(parsed.to)
            ? parsed.to.map((a: { text: string }) => a.text).join(", ")
            : parsed.to.text
          : "",
        date: parsed.date ? parsed.date.toISOString() : "",
        body,
        attachments,
      };
    } finally {
      lock.release();
    }
  }

  /**
   * Fetch a single image attachment (by filename, as listed in readEmail's
   * attachments[]) and return it base64-encoded for use as an MCP image
   * content block. Rejects non-image attachments and oversized files.
   */
  async getImageAttachment(messageId: string, filename: string): Promise<ImageAttachment> {
    const client = await this.getImap();
    const lock = await client.getMailboxLock("INBOX");
    try {
      const uid = await this.resolveUid(client, messageId);
      const parsed = await this.fetchParsed(client, uid, messageId);

      const attachment = (parsed.attachments ?? []).find((a) => a.filename === filename);
      if (!attachment) {
        throw new Error(
          `Attachment "${filename}" was not found on messageId "${messageId}". ` +
            `Call read_email first to see available attachment filenames.`
        );
      }
      if (!attachment.contentType.startsWith("image/")) {
        throw new Error(
          `Attachment "${filename}" is "${attachment.contentType}", not an image.`
        );
      }
      if (attachment.content.length > MAX_IMAGE_BYTES) {
        throw new Error(
          `Attachment "${filename}" is ${attachment.content.length} bytes, ` +
            `exceeding the ${MAX_IMAGE_BYTES}-byte limit for inline image retrieval.`
        );
      }

      return {
        filename,
        mimeType: attachment.contentType,
        base64: attachment.content.toString("base64"),
      };
    } finally {
      lock.release();
    }
  }

  /**
   * Prefer plain text; otherwise convert HTML to clean Markdown.
   */
  private extractCleanBody(parsed: ParsedMail): string {
    if (parsed.text && parsed.text.trim() !== "") {
      return parsed.text.trim();
    }
    if (parsed.html) {
      return this.turndown.turndown(parsed.html).trim();
    }
    return "(empty body)";
  }

  // ---- SMTP ---------------------------------------------------------------

  private getTransporter(): Transporter {
    if (this.transporter) return this.transporter;
    this.transporter = nodemailer.createTransport({
      ...SMTP_CONFIG,
      auth: { user: getLoginUser(), pass: getPassword(), method: "LOGIN" },
      pool: true,
      maxConnections: 3,
      connectionTimeout: 15000,
      // Exchange 2007's connector does not offer standard STARTTLS (only the
      // internal X-ANONYMOUSTLS), so we must not attempt to upgrade. AUTH LOGIN
      // is advertised on the plain submission port and used directly.
      ignoreTLS: true,
    });
    return this.transporter;
  }

  async sendEmail(opts: { to: string; subject: string; body: string }): Promise<string> {
    const transporter = this.getTransporter();
    const info = await transporter.sendMail({
      from: getEmailUser(),
      to: opts.to,
      subject: opts.subject,
      text: opts.body,
    });
    return info.messageId;
  }

  // ---- Lifecycle ----------------------------------------------------------

  async close(): Promise<void> {
    try {
      if (this.imap && this.imap.usable) await this.imap.logout();
    } catch {
      /* ignore */
    }
    this.imap = null;
    this.imapReady = null;
    if (this.transporter) {
      this.transporter.close();
      this.transporter = null;
    }
  }
}

export const emailClient = new EmailClient();
