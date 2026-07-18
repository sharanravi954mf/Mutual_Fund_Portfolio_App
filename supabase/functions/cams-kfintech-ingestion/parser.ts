import * as zip from "npm:@zip.js/zip.js";

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

interface DbfField {
  name: string;
  type: string;
  length: number;
}

// 1. Pure TypeScript DBF File Format Parser
function parseDbf(data: Uint8Array): Array<Record<string, any>> {
  const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
  
  // Read dBASE III header details
  const numRecords = view.getUint32(4, true);
  const headerLength = view.getUint16(8, true);
  const recordLength = view.getUint16(10, true);
  
  // Read field descriptors
  const fields: DbfField[] = [];
  let offset = 32;
  
  while (offset < data.length && data[offset] !== 0x0D) {
    // Field name (11 bytes, null-padded)
    const nameBytes = data.subarray(offset, offset + 11);
    let name = "";
    for (let i = 0; i < nameBytes.length; i++) {
      if (nameBytes[i] === 0) break;
      name += String.fromCharCode(nameBytes[i]);
    }
    name = name.trim();
    
    // Field type (1 byte at offset 11)
    const type = String.fromCharCode(data[offset + 11]);
    
    // Field length (1 byte at offset 16)
    const length = data[offset + 16];
    
    fields.push({ name, type, length });
    offset += 32;
  }
  
  // Records begin at offset headerLength
  let recordOffset = headerLength;
  const records: Array<Record<string, any>> = [];
  
  for (let r = 0; r < numRecords; r++) {
    if (recordOffset + recordLength > data.length) break;
    
    // Check deletion flag (0x2A '*' means deleted, 0x20 ' ' means active)
    const isDeleted = data[recordOffset] === 0x2A;
    if (!isDeleted) {
      const record: Record<string, any> = {};
      let fieldOffset = recordOffset + 1; // Skip the deletion flag
      
      for (const field of fields) {
        const fieldBytes = data.subarray(fieldOffset, fieldOffset + field.length);
        let valStr = "";
        for (let i = 0; i < fieldBytes.length; i++) {
          valStr += String.fromCharCode(fieldBytes[i]);
        }
        valStr = valStr.trim();
        
        // Convert to numeric if field is Numeric or Float
        if (field.type === 'N' || field.type === 'F') {
          record[field.name] = valStr ? parseFloat(valStr) : 0;
        } else {
          record[field.name] = valStr;
        }
        
        fieldOffset += field.length;
      }
      records.push(record);
    }
    
    recordOffset += recordLength;
  }
  
  return records;
}

// 2. Map xBase / dBASE DBF key-values to ParsedTransaction structure
function mapDbfRecordToTransaction(rec: Record<string, any>): ParsedTransaction {
  const getVal = (keys: string[]): any => {
    for (const k of keys) {
      if (rec[k] !== undefined) return rec[k];
      const upperK = k.toUpperCase();
      const match = Object.keys(rec).find(rk => rk.toUpperCase() === upperK);
      if (match) return rec[match];
    }
    return null;
  };

  const clientPan = String(getVal(["pan", "appl_pan", "pan_no", "pan_num"]) || "").toUpperCase().trim();
  const investorName = String(getVal(["inv_name", "holder_name", "name", "inv_nm"]) || "Unknown").trim();
  const folioNumber = String(getVal(["folio_no", "folio_num", "folio"]) || "").trim();
  const schemeCode = String(getVal(["scheme_cd", "sch_code", "scheme_code", "fm_code"]) || "").trim();
  const schemeName = String(getVal(["scheme_nm", "scheme_name", "fm_name", "sch_name"]) || "Unknown Scheme").trim();
  const fundHouse = String(getVal(["fund_house", "fm_house", "amc_name", "amc"]) || "Mutual Fund").trim();
  const category = String(getVal(["category", "scheme_cat", "cat"]) || "Mutual Fund").trim();
  
  const rawType = String(getVal(["trx_type", "tx_type", "type", "tr_type"]) || "").toUpperCase();
  let transactionType: "BUY" | "SELL" | "SWITCH" = "BUY";
  if (rawType.includes("SELL") || rawType.includes("RED") || rawType.includes("OUT")) {
    transactionType = "SELL";
  } else if (rawType.includes("SWITCH") || rawType.includes("SWI")) {
    transactionType = "SWITCH";
  }

  const units = parseFloat(getVal(["units", "qty", "unit_qty"]) || "0");
  const nav = parseFloat(getVal(["nav", "price", "rate"]) || "0");
  const amount = parseFloat(getVal(["amount", "amt", "trx_amt"]) || "0");
  
  const rawDate = getVal(["trx_date", "tx_date", "date", "execution_date"]);
  let date = new Date();
  if (rawDate) {
    const dStr = String(rawDate).trim();
    if (dStr.length === 8 && /^\d+$/.test(dStr)) {
      // YYYYMMDD format
      const y = parseInt(dStr.substring(0, 4));
      const m = parseInt(dStr.substring(4, 6)) - 1;
      const d = parseInt(dStr.substring(6, 8));
      date = new Date(y, m, d);
    } else {
      date = new Date(dStr);
    }
  }

  return {
    clientPan,
    investorName,
    folioNumber,
    schemeCode,
    schemeName,
    fundHouse,
    category,
    transactionType,
    units,
    nav,
    amount,
    date
  };
}

// 3. Schema and values validation helper
function validateParsedTransaction(tx: ParsedTransaction): string[] {
  const errors: string[] = [];
  if (!tx.folioNumber) errors.push("Folio number is missing");
  
  const panRegex = /^[A-Z]{5}[0-9]{4}[A-Z]$/;
  if (!tx.clientPan) {
    errors.push("PAN is missing");
  } else if (!panRegex.test(tx.clientPan.toUpperCase())) {
    errors.push(`Invalid PAN format: "${tx.clientPan}"`);
  }
  
  if (!tx.investorName) errors.push("Investor name is missing");
  if (!tx.schemeCode) errors.push("Scheme code is missing");
  if (!tx.schemeName) errors.push("Scheme name is missing");
  if (!tx.fundHouse) errors.push("Fund house is missing");
  if (!tx.category) errors.push("Category is missing");
  
  if (tx.transactionType !== "BUY" && tx.transactionType !== "SELL" && tx.transactionType !== "SWITCH") {
    errors.push(`Invalid transaction type: "${tx.transactionType}" (must be BUY, SELL, or SWITCH)`);
  }
  
  if (isNaN(tx.units) || tx.units <= 0) {
    errors.push(`Invalid units: "${tx.units}" (must be a positive number)`);
  }
  
  if (isNaN(tx.nav) || tx.nav < 0) {
    errors.push(`Invalid NAV: "${tx.nav}" (must be a non-negative number)`);
  }
  
  if (isNaN(tx.amount) || tx.amount < 0) {
    errors.push(`Invalid amount: "${tx.amount}" (must be a non-negative number)`);
  }
  
  if (isNaN(tx.date.getTime())) {
    errors.push(`Invalid date format: "${tx.date}"`);
  }
  
  return errors;
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
   * Supports password-protected ZIP archive extraction and binary DBF database parsing.
   */
  async *parseFileStream(filename: string, fileData: Uint8Array): AsyncGenerator<ParsedTransaction> {
    let dataToParse = fileData;
    let targetFilename = filename;

    // Check if attachment is a ZIP archive
    if (filename.toLowerCase().endsWith(".zip")) {
      console.log(`Unzipping password-protected archive: ${filename}`);
      try {
        const zipReader = new zip.ZipReader(new zip.Uint8ArrayReader(fileData), {
          password: this.decryptionPassword || "cams123"
        });
        const entries = await zipReader.getEntries();
        
        // Search for DBF, TXT, or CSV targets
        const targetEntry = entries.find(e => 
          e.filename.toLowerCase().endsWith(".dbf") || 
          e.filename.toLowerCase().endsWith(".txt") ||
          e.filename.toLowerCase().endsWith(".csv")
        );
        
        if (!targetEntry) {
          throw new Error("No parseable .dbf, .txt, or .csv files found inside ZIP archive.");
        }
        
        console.log(`Extracting file: ${targetEntry.filename}`);
        const uint8Writer = new zip.Uint8ArrayWriter();
        dataToParse = await (targetEntry as any).getData(uint8Writer);
        targetFilename = targetEntry.filename;
      } catch (err) {
        console.error("ZIP decompression failed:", err);
        throw new Error(`Failed to decrypt and extract ZIP archive: ${err instanceof Error ? err.message : String(err)}`);
      }
    }

    // Check if target file is a dBASE database file (.dbf)
    if (targetFilename.toLowerCase().endsWith(".dbf")) {
      console.log(`Parsing DBF database structure: ${targetFilename}`);
      try {
        const records = parseDbf(dataToParse);
        console.log(`Successfully extracted ${records.length} records from DBF.`);
        
        let rowNum = 0;
        for (const rec of records) {
          rowNum++;
          this.totalLinesProcessed++; // Map DBF records to lines processed for logging
          
          const transaction = mapDbfRecordToTransaction(rec);
          const validationErrors = validateParsedTransaction(transaction);
          
          if (validationErrors.length > 0) {
            this.totalErrors++;
            this.errors.push({
              line: JSON.stringify(rec),
              lineNumber: rowNum,
              reason: validationErrors.join(", ")
            });
            continue;
          }
          
          this.totalRecordsParsed++;
          yield transaction;
        }
        return;
      } catch (err) {
        console.error("DBF parsing failed:", err);
        throw new Error(`Failed to parse DBF database: ${err instanceof Error ? err.message : String(err)}`);
      }
    }

    // Default line-by-line fallback text parser for CSV/TXT
    const rawData = await this.decryptAttachmentIfNeeded(targetFilename, dataToParse);
    
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
      remaining = lines.pop() || "";

      for (const line of lines) {
        lineNum++;
        this.totalLinesProcessed++;
        const parsed = this.parseLine(line, targetFilename, lineNum);
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
      const parsed = this.parseLine(remaining, targetFilename, lineNum);
      if (parsed) {
        this.totalRecordsParsed++;
        yield parsed;
      }
    }
  }

  private async decryptAttachmentIfNeeded(filename: string, fileData: Uint8Array): Promise<Uint8Array> {
    return fileData;
  }

  private parseLine(line: string, filename: string, lineNum: number): ParsedTransaction | null {
    const trimmed = line.trim();
    if (!trimmed) return null;

    const lower = trimmed.toLowerCase();
    if (lower.includes("folio") && (lower.includes("pan") || lower.includes("scheme"))) {
      return null;
    }

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

    const transaction = {
      folioNumber: folio,
      clientPan: pan.toUpperCase(),
      investorName: name,
      schemeCode,
      schemeName,
      fundHouse,
      category,
      transactionType: type.toUpperCase() as "BUY" | "SELL" | "SWITCH",
      units: parseFloat(unitsStr),
      nav: parseFloat(navStr),
      amount: parseFloat(amountStr),
      date: new Date(dateStr)
    };

    const validationErrors = validateParsedTransaction(transaction);
    if (validationErrors.length > 0) {
      this.totalErrors++;
      this.errors.push({
        line: trimmed,
        lineNumber: lineNum,
        reason: validationErrors.join(", ")
      });
      return null;
    }

    return transaction;
  }
}
