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

export interface ParsingError {
  line: string;
  lineNumber: number;
  reason: string;
}

export class RtaFileParser {
  private decryptionPassword = Deno.env.get("RTA_DECRYPTION_PASSWORD") || "";

  // Track metrics for reporting/validation
  public totalLinesProcessed = 0;
  public totalRecordsParsed = 0;
  public totalErrors = 0;
  public errors: ParsingError[] = [];

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
    let lineNum = 0;

    while (!done) {
      const lines = (remaining + chunk).split(/\r?\n/);
      remaining = lines.pop() || ""; // Save trailing incomplete line

      for (const line of lines) {
        lineNum++;
        this.totalLinesProcessed++;
        const parsed = this.parseLine(line, filename, lineNum);
        if (parsed) {
          this.totalRecordsParsed++;
          yield parsed;
        }
      }

      const res = await reader.read();
      chunk = res.value;
      done = res.done;
    }

    if (remaining.trim()) {
      lineNum++;
      this.totalLinesProcessed++;
      const parsed = this.parseLine(remaining, filename, lineNum);
      if (parsed) {
        this.totalRecordsParsed++;
        yield parsed;
      }
    }
  }

  private async decryptAttachmentIfNeeded(filename: string, fileData: Uint8Array): Promise<Uint8Array> {
    // If ZIP or PDF, decrypt using Deno.env decryption password
    // Placeholder decryption implementation returning raw bytes
    return fileData;
  }

  private parseLine(line: string, filename: string, lineNum: number): ParsedTransaction | null {
    const trimmed = line.trim();
    if (!trimmed) return null;

    // Check if it is a header line (contains column headers instead of data)
    const lower = trimmed.toLowerCase();
    if (lower.includes("folio") && (lower.includes("pan") || lower.includes("scheme"))) {
      // Silently ignore header
      return null;
    }

    // Determine delimiter
    const delimiter = trimmed.includes(";") ? ";" : (trimmed.includes(",") ? "," : null);
    if (!delimiter) {
      this.totalErrors++;
      this.errors.push({
        line: trimmed,
        lineNumber: lineNum,
        reason: "No valid delimiter (; or ,) found in line."
      });
      return null;
    }

    const parts = trimmed.split(delimiter).map(p => p.trim());
    if (parts.length !== 12) {
      this.totalErrors++;
      this.errors.push({
        line: trimmed,
        lineNumber: lineNum,
        reason: `Incorrect number of fields: expected 12, got ${parts.length}`
      });
      return null;
    }

    const [
      folio,
      pan,
      name,
      schemeCode,
      schemeName,
      fundHouse,
      category,
      type,
      unitsStr,
      navStr,
      amountStr,
      dateStr
    ] = parts;

    const validationErrors: string[] = [];

    // 1. Folio Number Validation
    if (!folio) {
      validationErrors.push("Folio number is missing");
    }

    // 2. PAN Validation
    const normalizedPan = pan.toUpperCase();
    const panRegex = /^[A-Z]{5}[0-9]{4}[A-Z]$/;
    if (!pan) {
      validationErrors.push("PAN is missing");
    } else if (!panRegex.test(normalizedPan)) {
      validationErrors.push(`Invalid PAN format: "${pan}"`);
    }

    // 3. Name Validation
    if (!name) {
      validationErrors.push("Investor name is missing");
    }

    // 4. Scheme Code Validation
    if (!schemeCode) {
      validationErrors.push("Scheme code is missing");
    }

    // 5. Scheme Name Validation
    if (!schemeName) {
      validationErrors.push("Scheme name is missing");
    }

    // 6. Fund House Validation
    if (!fundHouse) {
      validationErrors.push("Fund house is missing");
    }

    // 7. Category Validation
    if (!category) {
      validationErrors.push("Category is missing");
    }

    // 8. Transaction Type Validation
    const normalizedType = type.toUpperCase();
    if (normalizedType !== "BUY" && normalizedType !== "SELL" && normalizedType !== "SWITCH") {
      validationErrors.push(`Invalid transaction type: "${type}" (must be BUY, SELL, or SWITCH)`);
    }

    // 9. Units Validation
    const units = parseFloat(unitsStr);
    if (isNaN(units) || units <= 0) {
      validationErrors.push(`Invalid units: "${unitsStr}" (must be a positive number)`);
    }

    // 10. NAV Validation
    const nav = parseFloat(navStr);
    if (isNaN(nav) || nav < 0) {
      validationErrors.push(`Invalid NAV: "${navStr}" (must be a non-negative number)`);
    }

    // 11. Amount Validation
    const amount = parseFloat(amountStr);
    if (isNaN(amount) || amount < 0) {
      validationErrors.push(`Invalid amount: "${amountStr}" (must be a non-negative number)`);
    }

    // 12. Date Validation
    const date = new Date(dateStr);
    if (isNaN(date.getTime())) {
      validationErrors.push(`Invalid date format: "${dateStr}"`);
    }

    if (validationErrors.length > 0) {
      this.totalErrors++;
      this.errors.push({
        line: trimmed,
        lineNumber: lineNum,
        reason: validationErrors.join(", ")
      });
      return null;
    }

    return {
      folioNumber: folio,
      clientPan: normalizedPan,
      investorName: name,
      schemeCode: schemeCode,
      schemeName: schemeName,
      fundHouse: fundHouse,
      category: category,
      transactionType: normalizedType as "BUY" | "SELL" | "SWITCH",
      units,
      nav,
      amount,
      date
    };
  }
}
