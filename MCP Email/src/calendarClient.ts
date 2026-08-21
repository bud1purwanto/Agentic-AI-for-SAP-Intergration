import EWS from "node-ews";

function getEmailUser(): string {
  return process.env.EMAIL_USER?.trim() || "";
}

// Certificate on this Exchange server is issued for *.trst.co.id.
// mail.trst.co.id resolves to the same IP (192.168.1.15).
const EWS_HOST = process.env.EWS_HOST?.trim() ?? "https://mail.trst.co.id";

function getCreds() {
  const pass = process.env.EMAIL_PASS?.trim();
  if (!pass) throw new Error("EMAIL_PASS is not set.");
  const username = process.env.EMAIL_LOGIN_USER?.trim();
  if (!username) {
    throw new Error(
      "EMAIL_LOGIN_USER environment variable is not set. " +
        "Set it (e.g. in a .env file) before starting the server."
    );
  }
  return {
    username,
    password: pass,
    host: EWS_HOST,
  };
}

let ewsInstance: InstanceType<typeof EWS> | null = null;

function getEws(): InstanceType<typeof EWS> {
  if (ewsInstance) return ewsInstance;
  const creds = getCreds();
  ewsInstance = new EWS({
    username: creds.username,
    password: creds.password,
    host: creds.host,
    auth: "ntlm",
  });
  return ewsInstance;
}

export interface CalendarItem {
  itemId: string;
  subject: string;
  start: string;
  end: string;
  location: string;
  organizer: string;
  isAllDay: boolean;
  status: string;
}

/**
 * Fetch calendar items for a date range using EWS FindItem + CalendarView.
 * startDate / endDate are ISO date strings (YYYY-MM-DD).
 */
export async function getCalendarItems(
  startDate: string,
  endDate: string
): Promise<CalendarItem[]> {
  const ews = getEws();

  // Build CalendarView date range (start of day → end of day).
  const startDt = new Date(startDate);
  startDt.setHours(0, 0, 0, 0);
  const endDt = new Date(endDate);
  endDt.setHours(23, 59, 59, 999);

  const ewsArgs = {
    attributes: {
      Traversal: "Shallow",
    },
    ItemShape: {
      BaseShape: "AllProperties",
    },
    CalendarView: {
      attributes: {
        StartDate: startDt.toISOString(),
        EndDate: endDt.toISOString(),
        MaxEntriesReturned: 50,
      },
    },
    ParentFolderIds: {
      DistinguishedFolderId: {
        attributes: { Id: "calendar" },
      },
    },
  };

  let result: any;
  try {
    result = await ews.run("FindItem", ewsArgs);
  } catch (err: any) {
    // Provide a clear error if EWS is unreachable or auth fails.
    throw new Error(`EWS FindItem failed: ${err?.message ?? err}`);
  }

  const items =
    result?.ResponseMessages?.FindItemResponseMessage?.RootFolder?.Items
      ?.CalendarItem;

  if (!items) return [];

  // Normalise: single item comes back as object, multiple as array.
  const list: any[] = Array.isArray(items) ? items : [items];

  return list.map((item: any) => ({
    itemId: item.ItemId?.attributes?.Id ?? "",
    subject: item.Subject ?? "(no subject)",
    start: item.Start ?? "",
    end: item.End ?? "",
    location: item.Location ?? "",
    organizer:
      item.Organizer?.Mailbox?.Name ??
      item.Organizer?.Mailbox?.EmailAddress ??
      "",
    isAllDay: item.IsAllDayEvent === "true",
    status: item.MyResponseType ?? item.LegacyFreeBusyStatus ?? "",
  }));
}

/** Format a calendar item for human-readable display. */
export function formatCalendarItem(item: CalendarItem): string {
  const start = item.start ? new Date(item.start) : null;
  const end = item.end ? new Date(item.end) : null;

  const timeStr = item.isAllDay
    ? "All Day"
    : start && end
    ? `${start.toLocaleTimeString("id-ID", { hour: "2-digit", minute: "2-digit" })} – ${end.toLocaleTimeString("id-ID", { hour: "2-digit", minute: "2-digit" })}`
    : "";

  const parts = [`📅 **${item.subject}**`, `⏰ ${timeStr}`];
  if (item.location) parts.push(`📍 ${item.location}`);
  const myEmail = getEmailUser();
  if (item.organizer && myEmail && item.organizer !== myEmail) parts.push(`👤 ${item.organizer}`);
  if (item.status) parts.push(`✅ ${item.status}`);

  return parts.join(" | ");
}
