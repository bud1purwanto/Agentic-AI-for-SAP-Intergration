import "dotenv/config";
import { emailClient } from "./emailClient.js";

async function main() {
  console.log("=== MCP Email Connector — connection test ===\n");

  console.log("[1/2] Testing IMAP (read) ...");
  try {
    const emails = await emailClient.searchEmails({ maxResults: 3, unreadOnly: false });
    console.log(`  OK — INBOX reachable. Showing up to 3 recent emails:`);
    for (const e of emails) {
      console.log(`   - ${e.date} | ${e.from} | ${e.subject}`);
    }
    if (emails.length === 0) {
      console.log("   (inbox empty or no matches)");
    } else {
      console.log("\n[Reading Latest Email Detail] ...");
      const detail = await emailClient.readEmail(emails[0].messageId);
      console.log(`   From: ${detail.from}`);
      console.log(`   To: ${detail.to}`);
      console.log(`   Date: ${detail.date}`);
      console.log(`   Subject: ${detail.subject}`);
      console.log(`   Attachments: ${detail.attachments.length}`);
      console.log(`   Body:\n----------------------------------------\n${detail.body}\n----------------------------------------`);
    }
  } catch (err) {
    console.error("  FAILED:", err instanceof Error ? err.message : err);
  }

  console.log("\n[2/2] Testing SMTP (send transport) ...");
  try {
    // verify() checks auth + connectivity WITHOUT sending an email.
    const transporter = (emailClient as any).getTransporter();
    await transporter.verify();
    console.log("  OK — SMTP login & connection verified.");
  } catch (err) {
    console.error("  FAILED:", err instanceof Error ? err.message : err);
  }

  await emailClient.close();
  console.log("\nDone.");
  process.exit(0);
}

main();
