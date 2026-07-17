import { Buffer } from "https://deno.land/std@0.177.0/node/buffer.ts";

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
    this.hostname = Deno.env.get("IMAP_HOST") || "";
    this.port = parseInt(Deno.env.get("IMAP_PORT") || "993");
    this.user = Deno.env.get("IMAP_USER") || "";
    this.pass = Deno.env.get("IMAP_PASSWORD") || "";
  }

  /**
   * Connects via IMAP over TLS, logins, searches for reports, and downloads attachments.
   */
  async fetchNewReportAttachments(): Promise<EmailAttachment[]> {
    if (!this.hostname || !this.user || !this.pass) {
      throw new Error("IMAP credentials are not fully configured in environment variables.");
    }

    const conn = await Deno.connectTls({ hostname: this.hostname, port: this.port });
    const reader = conn.readable.getReader();
    const writer = conn.writable.getWriter();
    const encoder = new TextEncoder();
    const decoder = new TextDecoder();

    const sendCmd = async (cmd: string): Promise<string> => {
      await writer.write(encoder.encode(cmd + "\r\n"));
      let response = "";
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        response += decoder.decode(value);
        if (response.includes("\n") && response.trim().endsWith("OK") || response.includes("BAD") || response.includes("NO")) {
          break;
        }
      }
      return response;
    };

    try {
      // 1. Read Greeting
      const greeting = await reader.read();
      
      // 2. Login
      await sendCmd(`A1 LOGIN "${this.user}" "${this.pass}"`);

      // 3. Select Inbox
      await sendCmd(`A2 SELECT INBOX`);

      // 4. Search for unread emails from RTAs with files
      // We search for UNSEEN emails containing RTA addresses
      const searchRes = await sendCmd(`A3 SEARCH UNSEEN OR FROM "cams@camsonline.com" FROM "kfintech@kfintech.com"`);
      
      // Parse message numbers from search result
      const idsMatch = searchRes.match(/\* SEARCH ([\d\s]+)/);
      if (!idsMatch || !idsMatch[1].trim()) {
        conn.close();
        return []; // No new reports
      }

      const msgIds = idsMatch[1].trim().split(/\s+/);
      const attachments: EmailAttachment[] = [];

      for (const id of msgIds) {
        // Fetch raw message RFC822 or structure
        const fetchRes = await sendCmd(`A4 FETCH ${id} (BODY.PEEK[])`);
        // Extract attachment data (simplified MIME boundary extraction in this pipeline stub)
        const parsed = this.parseMimeAttachments(fetchRes);
        attachments.push(...parsed);
        
        // Mark as read after successful extraction
        await sendCmd(`A5 STORE ${id} +FLAGS (\\Seen)`);
      }

      // Logout & Close
      await sendCmd(`A6 LOGOUT`);
      conn.close();
      return attachments;
    } catch (e) {
      conn.close();
      throw e;
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
}
