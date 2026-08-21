import { z } from "zod";
import { emailClient } from "./emailClient.js";
import { getCalendarItems, formatCalendarItem } from "./calendarClient.js";

/**
 * Tool input schemas (Zod). The raw shapes are exported so they can be passed
 * directly to the MCP server's registerTool() inputSchema field.
 */

export const searchEmailsShape = {
  query: z
    .string()
    .optional()
    .describe('Optional keyword to match in subject/body, e.g. "error", "issue".'),
  from: z
    .string()
    .optional()
    .describe(
      'Filter by sender name or email address, e.g. "Wafi" or "wafi.makarim@trst.co.id". ' +
      'Use this (not query) when the user asks for emails FROM a specific person.'
    ),
  maxResults: z
    .number()
    .int()
    .positive()
    .default(5)
    .describe("Maximum number of emails to return (default 5)."),
  unreadOnly: z
    .boolean()
    .default(false)
    .describe("If true, only return unread (unseen) emails."),
};

export const readEmailShape = {
  messageId: z
    .string()
    .describe('The Message ID returned by search_emails (RFC Message-ID or "uid:<n>").'),
};

export const sendEmailShape = {
  to: z.string().describe("Recipient email address."),
  subject: z.string().describe("Email subject line."),
  body: z.string().describe("Email body in plain text / markdown."),
};

export const getCalendarShape = {
  date: z
    .string()
    .optional()
    .describe(
      "Start date in YYYY-MM-DD format (default: today). " +
      "E.g. \"2026-07-09\" for a specific day."
    ),
  daysAhead: z
    .number()
    .int()
    .min(0)
    .max(30)
    .default(0)
    .describe(
      "How many additional days to include after 'date' (default 0 = only that day). " +
      "Use 1 for today + tomorrow, 4 for a work week, etc."
    ),
};

export const getEmailImageShape = {
  messageId: z
    .string()
    .describe('The Message ID of the email (RFC Message-ID or "uid:<n>").'),
  filename: z
    .string()
    .describe(
      'Attachment filename, exactly as listed in read_email\'s "attachments" array.'
    ),
};

const searchEmailsSchema = z.object(searchEmailsShape);
const readEmailSchema = z.object(readEmailShape);
const sendEmailSchema = z.object(sendEmailShape);
const getCalendarSchema = z.object(getCalendarShape);
const getEmailImageSchema = z.object(getEmailImageShape);

type ContentBlock =
  | { type: "text"; text: string }
  | { type: "image"; data: string; mimeType: string };
type TextResult = { content: ContentBlock[]; isError?: boolean };

function ok(data: unknown): TextResult {
  return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
}

function fail(err: unknown): TextResult {
  const message = err instanceof Error ? err.message : String(err);
  return { content: [{ type: "text", text: `Error: ${message}` }], isError: true };
}

// ---- Handlers -------------------------------------------------------------

export async function handleSearchEmails(args: unknown): Promise<TextResult> {
  try {
    const { query, from, maxResults, unreadOnly } = searchEmailsSchema.parse(args);
    const results = await emailClient.searchEmails({ query, from, maxResults, unreadOnly });
    return ok({ count: results.length, emails: results });
  } catch (err) {
    return fail(err);
  }
}

export async function handleReadEmail(args: unknown): Promise<TextResult> {
  try {
    const { messageId } = readEmailSchema.parse(args);
    const detail = await emailClient.readEmail(messageId);
    return ok(detail);
  } catch (err) {
    return fail(err);
  }
}

export async function handleGetCalendar(args: unknown): Promise<TextResult> {
  try {
    const { date, daysAhead } = getCalendarSchema.parse(args);

    // Default to today in local time (WIB UTC+7 / Asia/Jakarta).
    const tz = process.env.TIMEZONE || "Asia/Jakarta";
    const startDate =
      date ?? new Intl.DateTimeFormat("en-CA", { timeZone: tz }).format(new Date());

    // End date = startDate + daysAhead.
    const endDt = new Date(startDate);
    endDt.setDate(endDt.getDate() + (daysAhead ?? 0));
    const endDate = endDt.toISOString().slice(0, 10);

    const items = await getCalendarItems(startDate, endDate);

    if (items.length === 0) {
      return ok({
        date: startDate,
        endDate,
        count: 0,
        message: "Tidak ada agenda pada rentang tanggal ini.",
        items: [],
      });
    }

    // Sort by start time.
    items.sort((a, b) => (a.start < b.start ? -1 : 1));

    return ok({
      date: startDate,
      endDate,
      count: items.length,
      items: items.map((item) => ({
        ...item,
        formatted: formatCalendarItem(item),
      })),
    });
  } catch (err) {
    return fail(err);
  }
}

export async function handleGetEmailImage(args: unknown): Promise<TextResult> {
  try {
    const { messageId, filename } = getEmailImageSchema.parse(args);
    const image = await emailClient.getImageAttachment(messageId, filename);
    return {
      content: [
        { type: "text", text: `Image "${image.filename}" (${image.mimeType}):` },
        { type: "image", data: image.base64, mimeType: image.mimeType },
      ],
    };
  } catch (err) {
    return fail(err);
  }
}

export async function handleSendEmail(args: unknown): Promise<TextResult> {
  try {
    const { to, subject, body } = sendEmailSchema.parse(args);
    const messageId = await emailClient.sendEmail({ to, subject, body });
    return ok({ status: "sent", messageId, to, subject });
  } catch (err) {
    return fail(err);
  }
}
