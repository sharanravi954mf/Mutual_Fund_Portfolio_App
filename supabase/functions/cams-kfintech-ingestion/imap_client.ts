import { Buffer } from "https://deno.land/std@0.177.0/node/buffer.ts";
import { ImapFlow } from "https://esm.sh/imapflow@1.0.155";

export interface EmailAttachment {
  filename: string;
  contentType: string;
  data: Uint8Array;
}

export class ImapClient {
  private hostname: string;
  private port: number;
  private user: string;
  private pass: string;

  constructor() {
    this.hostname = Deno.env.get("IMAP_HOST") || "imap.gmail.com";
    this.port = parseInt(Deno.env.get("IMAP_PORT") || "993");
    this.user = Deno.env.get("IMAP_USER") || "";
    this.pass = Deno.env.get("IMAP_PASSWORD") || "";
  }

  /**
   * Connects via IMAP using ImapFlow, searches for reports, and downloads attachments or parses body links.
   */
  async fetchNewReportAttachments(): Promise<EmailAttachment[]> {
    if (!this.hostname || !this.user || !this.pass) {
      throw new Error("IMAP credentials are not fully configured in environment variables.");
    }

    const client = new ImapFlow({
      host: this.hostname,
      port: this.port,
      secure: this.port === 993,
      auth: { user: this.user, pass: this.pass },
      logger: false
    });

    await client.connect();
    const lock = await client.getMailboxLock("INBOX");
    const attachments: EmailAttachment[] = [];

    try {
      // 1. Search for unseen emails containing standard RTA attachments (cams@camsonline.com or kfintech@kfintech.com)
      const searchResult1 = await client.search({
        seen: false,
        or: [
          { from: "cams@camsonline.com" },
          { from: "kfintech@kfintech.com" }
        ]
      }, { uid: true });

      for (const uid of searchResult1) {
        const message = await client.fetchOne(uid, { source: true }, { uid: true });
        if (message && message.source) {
          const rawEmail = message.source.toString();
          const parsed = this.parseMimeAttachments(rawEmail);
          attachments.push(...parsed);

          // Mark as read after successful extraction
          await client.messageFlagsAdd(uid, ["\\Seen"], { uid: true });
        }
      }

      // 2. Search for unseen CAMS Mailback Server WBR9 reports
      const searchResult2 = await client.search({
        seen: false,
        from: "CAMS Mailback Server",
        subject: "WBR9"
      }, { uid: true });

      for (const uid of searchResult2) {
        const message = await client.fetchOne(uid, { source: true }, { uid: true });
        if (message && message.source) {
          const emailText = message.source.toString();
          const decodedText = this.decodeQuotedPrintable(emailText);
          // Regular Expression targeting the secure DownloadURL parameter inside the HTML table layout
          const urlRegex = /https:\/\/mailback\d+\.camsonline\.com\/mailback_result\/[A-Za-z0-9]+/g;
          const match = decodedText.match(urlRegex);

          if (match) {
            const downloadUrl = match[0];
            const response = await fetch(downloadUrl);
            if (!response.ok) {
              throw new Error(`Failed to download CAMS WBR9 report from: ${downloadUrl}`);
            }
            const fileData = new Uint8Array(await response.arrayBuffer());

            // Extract filename from headers or use default
            let filename = "cams_wbr9_report.txt";
            const contentDisposition = response.headers.get("content-disposition");
            if (contentDisposition) {
              const fileMatch = contentDisposition.match(/filename="?([^"\s]+)"?/i);
              if (fileMatch) {
                filename = fileMatch[1];
              }
            }
            const contentType = response.headers.get("content-type") || "text/plain";
            attachments.push({
              filename,
              contentType,
              data: fileData
            });

            // Mark as read after successful extraction
            await client.messageFlagsAdd(uid, ["\\Seen"], { uid: true });
          }
        }
      }

      return attachments;
    } finally {
      lock.release();
      await client.logout();
    }
  }

  private parseMimeAttachments(rawEmail: string): EmailAttachment[] {
    const list: EmailAttachment[] = [];
    // Regular expression or custom logic to find Base64 segments with content-disposition filenames
    const boundaryMatch = rawEmail.match(/boundary="?([^"\s]+)"?/i);
    if (!boundaryMatch) return [];

    const boundary = boundaryMatch[1];
    const parts = rawEmail.split(`--${boundary}`);

    for (const part of parts) {
      if (part.includes("Content-Disposition: attachment")) {
        const fileMatch = part.match(/filename="?([^"\s]+)"?/i);
        const ctMatch = part.match(/Content-Type:\s*([^;\s]+)/i);
        
        if (fileMatch) {
          const filename = fileMatch[1];
          const contentType = ctMatch ? ctMatch[1] : "application/octet-stream";
          
          // Locate base64 content
          const splitPart = part.split(/\r?\n\r?\n/);
          if (splitPart.length > 1) {
            const base64Content = splitPart.slice(1).join("").replace(/\s+/g, "");
            const binaryVal = Uint8Array.from(Buffer.from(base64Content, "base64"));
            list.push({ filename, contentType, data: binaryVal });
          }
        }
      }
    }
    return list;
  }

  private decodeQuotedPrintable(str: string): string {
    return str
      .replace(/=\r?\n/g, "")
      .replace(/=([0-9A-F]{2})/gi, (_, hex) => String.fromCharCode(parseInt(hex, 16)));
  }
}
