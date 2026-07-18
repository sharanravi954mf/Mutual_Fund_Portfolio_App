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
   * Connects via IMAP, searches for reports, and downloads attachments or parses body links.
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
      // 1. Unified search for unseen emails from CAMS/KFintech or containing WBR9
      const searchResult = await client.search({
        seen: false,
        or: [
          { subject: "WBR9" },
          { from: "donotreply@camsonline.com" },
          { from: "cams@camsonline.com" },
          { from: "kfintech@kfintech.com" }
        ]
      }, { uid: true });

      console.log(`IMAP Search found ${searchResult.length} unseen matching emails.`);

      for (const uid of searchResult) {
        const message = await client.fetchOne(uid, { source: true }, { uid: true });
        if (message && message.source) {
          const rawEmail = message.source.toString();
          
          // A. Try parsing direct MIME attachments
          const mimeAttachments = this.parseMimeAttachments(rawEmail);
          if (mimeAttachments.length > 0) {
            attachments.push(...mimeAttachments);
          }

          // B. Try extracting DownloadURL from email body (e.g. CAMS WBR9 links)
          const decodedText = this.decodeQuotedPrintable(rawEmail);
          // Match standard cams mailback download links (supporting .zip, .dbf, etc.)
          const urlRegex = /https:\/\/mailback\d+\.camsonline\.com\/mailback_result\/[^\s"<>']+/g;
          const matches = decodedText.match(urlRegex);

          if (matches) {
            for (const downloadUrl of matches) {
              console.log(`Found CAMS DownloadURL in email body: ${downloadUrl}`);
              try {
                const response = await fetch(downloadUrl);
                if (!response.ok) {
                  console.error(`Failed to fetch report from: ${downloadUrl} (status: ${response.status})`);
                  continue;
                }
                const fileData = new Uint8Array(await response.arrayBuffer());

                let filename = "cams_wbr9_report.zip";
                const contentDisposition = response.headers.get("content-disposition");
                if (contentDisposition) {
                  const fileMatch = contentDisposition.match(/filename="?([^"\s]+)"?/i);
                  if (fileMatch) {
                    filename = fileMatch[1];
                  }
                } else {
                  // Fallback filename extraction from URL
                  const urlParts = downloadUrl.split("/");
                  const lastPart = urlParts[urlParts.length - 1];
                  if (lastPart.toLowerCase().endsWith(".zip") || lastPart.toLowerCase().endsWith(".dbf")) {
                    filename = lastPart;
                  }
                }

                const contentType = response.headers.get("content-type") || "application/zip";
                attachments.push({
                  filename,
                  contentType,
                  data: fileData
                });
              } catch (fetchErr) {
                console.error(`Error downloading report from URL: ${downloadUrl}`, fetchErr);
              }
            }
          }

          // Mark email as read after processing
          await client.messageFlagsAdd(uid, ["\\Seen"], { uid: true });
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
          
          const splitPart = part.split(/\r?\n\r?\n/);
          if (splitPart.length > 1) {
            const base64Content = splitPart.slice(1).join("").replace(/\s+/g, "");
            try {
              const binaryVal = Uint8Array.from(Buffer.from(base64Content, "base64"));
              list.push({ filename, contentType, data: binaryVal });
            } catch (err) {
              console.error(`Failed to decode MIME attachment: ${filename}`, err);
            }
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
