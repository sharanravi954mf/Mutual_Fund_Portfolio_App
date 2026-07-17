import { ReadableStreamDefaultReader } from "https://deno.land/std@0.177.0/streams/mod.ts";

export interface ParsedTransaction {
  clientPan: string;
  investorName: string;
  folioNumber: string;
  schemeCode: string;
  schemeName: string;
  fundHouse: string;
  category: string;
  transactionType: "BUY" | "SELL" | "SWITCH";
  units: number;
  nav: number;
  amount: number;
  date: Date;
}

export class RtaFileParser {
  private decryptionPassword = Deno.env.get("RTA_DECRYPTION_PASSWORD") || "";

  /**
   * Decrypts (if needed) and parses an RTA file.
   * Leverages stream readers to process line-by-line avoiding OOM.
   */
  async *parseFileStream(filename: string, fileData: Uint8Array): AsyncGenerator<ParsedTransaction> {
    const rawData = await this.decryptAttachmentIfNeeded(filename, fileData);
    
    // Convert Uint8Array to stream
    const stream = new ReadableStream({
      start(controller) {
        controller.enqueue(rawData);
        controller.close();
      }
    });

    const textStream = stream.pipeThrough(new TextDecoderStream());
    const reader = textStream.getReader();
    let { value: chunk, done } = await reader.read();
    let remaining = "";

    while (!done) {
      const lines = (remaining + chunk).split(/\r?\n/);
      remaining = lines.pop() || ""; // Save trailing incomplete line

      for (const line of lines) {
        if (!line.trim()) continue;
        const parsed = this.parseLine(line, filename);
        if (parsed) {
          yield parsed;
        }
      }

      const res = await reader.read();
      chunk = res.value;
      done = res.done;
    }

    if (remaining.trim()) {
      const parsed = this.parseLine(remaining, filename);
      if (parsed) yield parsed;
    }
  }

  private async decryptAttachmentIfNeeded(filename: string, fileData: Uint8Array): Promise<Uint8Array> {
    // If ZIP or PDF, decrypt using Deno.env decryption password
    // Placeholder decryption implementation returning raw bytes
    return fileData;
  }

  private parseLine(line: string, filename: string): ParsedTransaction | null {
    // CAMS TXT/CSV format regex matcher:
    // Format usually is: Folio;PAN;Name;SchemeCode;SchemeName;FundHouse;Category;Type;Units;NAV;Amount;Date
    if (filename.toLowerCase().endsWith(".txt") || filename.toLowerCase().endsWith(".csv")) {
      const camsRegex = /^(?<folio>\d+);(?<pan>\w{10});(?<name>[^;]+);(?<scheme_code>\w+);(?<scheme_name>[^;]+);(?<fund_house>[^;]+);(?<category>[^;]+);(?<type>BUY|SELL|SWITCH);(?<units>\d+\.\d+);(?<nav>\d+\.\d+);(?<amount>\d+\.\d+);(?<date>\d{4}-\d{2}-\d{2})$/i;
      
      const match = line.match(camsRegex);
      if (match && match.groups) {
        const g = match.groups;
        return {
          folioNumber: g.folio,
          clientPan: g.pan.toUpperCase(),
          investorName: g.name.trim(),
          schemeCode: g.scheme_code.trim(),
          schemeName: g.scheme_name.trim(),
          fundHouse: g.fund_house.trim(),
          category: g.category.trim(),
          transactionType: g.type.toUpperCase() as "BUY" | "SELL" | "SWITCH",
          units: parseFloat(g.units),
          nav: parseFloat(g.nav),
          amount: parseFloat(g.amount),
          date: new Date(g.date),
        };
      }
    }
    return null;
  }
}
