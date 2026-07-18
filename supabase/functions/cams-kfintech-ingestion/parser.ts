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

  // CAMS WBR9 Blueprint Schema
  foliochk: string;
  inv_name: string;
  address1: string;
  address2: string;
  address3: string;
  city: string;
  pincode: string;
  product: string;
  sch_name: string;
  rep_date: Date;
  clos_bal: number;
  rupee_bal: number;
  pan_no: string;
  joint1_pan: string;
  joint2_pan: string;
  guard_pan: string;
  email: string;
  mobile_no: string;
  bank_name: string;
  branch: string;
  ac_type: string;
  ac_no: string;
  ifsc_code: string;
  nom_name: string;
  relation: string;
  nom_percen: number;
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

function parseDecimal(val: any): number {
  const parsed = parseFloat(val);
  if (isNaN(parsed)) return 0;
  // Format/align decimals up to 6 decimal positions
  return Math.round(parsed * 1000000) / 1000000;
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

// 2. Map CAMS WBR9 keys to dynamic ParsedTransaction model
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

  // CAMS WBR9 Explicit Alphanumeric, Date and Numeric Attributes
  const foliochk = String(getVal(["foliochk", "folio_no", "folio"]) || "").trim();
  const inv_name = String(getVal(["inv_name", "holder_name", "name", "inv_nm"]) || "Unknown").trim();
  const address1 = String(getVal(["address1", "add1"]) || "").trim();
  const address2 = String(getVal(["address2", "add2"]) || "").trim();
  const address3 = String(getVal(["address3", "add3"]) || "").trim();
  const city = String(getVal(["city"]) || "").trim();
  const pincode = String(getVal(["pincode", "pin"]) || "").trim();
  const product = String(getVal(["product", "prodcode", "scheme_cd", "sch_code", "fm_code"]) || "").trim();
  const sch_name = String(getVal(["sch_name", "scheme", "scheme_nm", "scheme_name", "fm_name"]) || "Unknown Scheme").trim();
  
  const rawRepDate = getVal(["rep_date", "trx_date", "tx_date", "date", "execution_date"]);
  let rep_date = new Date();
  if (rawRepDate) {
    const dStr = String(rawRepDate).trim();
    if (dStr.length === 8 && /^\d+$/.test(dStr)) {
      // YYYYMMDD format support
      const y = parseInt(dStr.substring(0, 4));
      const m = parseInt(dStr.substring(4, 6)) - 1;
      const d = parseInt(dStr.substring(6, 8));
      rep_date = new Date(y, m, d);
    } else {
      rep_date = new Date(dStr);
    }
  }
  
  // Align decimals up to 6 decimal positions
  const clos_bal = parseDecimal(getVal(["clos_bal", "units", "qty", "unit_qty"]));
  const rupee_bal = parseDecimal(getVal(["rupee_bal", "amount", "amt", "trx_amt"]));
  
  const pan_no = String(getVal(["pan_no", "pan", "appl_pan"]) || "").toUpperCase().trim();
  const joint1_pan = String(getVal(["joint1_pan"]) || "").toUpperCase().trim();
  const joint2_pan = String(getVal(["joint2_pan"]) || "").toUpperCase().trim();
  const guard_pan = String(getVal(["guard_pan"]) || "").toUpperCase().trim();
  
  const email = String(getVal(["email"]) || "").trim();
  const mobile_no = String(getVal(["mobile_no", "mobile"]) || "").trim();
  
  const bank_name = String(getVal(["bank_name", "bank"]) || "").trim();
  const branch = String(getVal(["branch"]) || "").trim();
  const ac_type = String(getVal(["ac_type"]) || "").trim();
  const ac_no = String(getVal(["ac_no", "acno"]) || "").trim();
  const ifsc_code = String(getVal(["ifsc_code", "ifsc"]) || "").trim();
  
  const nom_name = String(getVal(["nom_name", "nominee"]) || "").trim();
  const relation = String(getVal(["relation"]) || "").trim();
  const nom_percen = parseDecimal(getVal(["nom_percen", "nominee_percent"]));

  // Backward compatible mappings for portfolios sync
  const clientPan = pan_no;
  const investorName = inv_name;
  const folioNumber = foliochk;
  const schemeCode = product;
  const schemeName = sch_name;
  const fundHouse = String(getVal(["fund_house", "fm_house", "amc_name", "amc"]) || "Mutual Fund").trim();
  const category = String(getVal(["category", "scheme_cat", "cat"]) || "Mutual Fund").trim();
  
  const rawType = String(getVal(["trx_type", "tx_type", "type", "tr_type"]) || "").toUpperCase();
  let transactionType: "BUY" | "SELL" | "SWITCH" = "BUY";
  if (rawType.includes("SELL") || rawType.includes("RED") || rawType.includes("OUT") || clos_bal < 0) {
    transactionType = "SELL";
  } else if (rawType.includes("SWITCH") || rawType.includes("SWI")) {
    transactionType = "SWITCH";
  }

  const units = Math.abs(clos_bal);
  const amount = Math.abs(rupee_bal);
  const navVal = parseFloat(getVal(["nav", "price", "rate"]) || "0");
  const nav = navVal > 0 ? navVal : (units > 0 ? Math.round((amount / units) * 10000) / 10000 : 0);

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
    date: rep_date,

    foliochk,
    inv_name,
    address1,
    address2,
    address3,
    city,
    pincode,
    product,
    sch_name,
    rep_date,
    clos_bal,
    rupee_bal,
    pan_no,
    joint1_pan,
    joint2_pan,
    guard_pan,
    email,
    mobile_no,
    bank_name,
    branch,
    ac_type,
    ac_no,
    ifsc_code,
    nom_name,
    relation,
    nom_percen
  };
}

// 3. Schema and values validation helper
function validateParsedTransaction(tx: ParsedTransaction): string[] {
  const errors: string[] = [];
  if (!tx.foliochk) errors.push("Folio number is missing");
  
  const panRegex = /^[A-Z]{5}[0-9]{4}[A-Z]$/;
  if (!tx.pan_no) {
    errors.push("PAN is missing");
  } else if (!panRegex.test(tx.pan_no.toUpperCase())) {
    errors.push(`Invalid PAN format: "${tx.pan_no}"`);
  }
  
  if (!tx.inv_name) errors.push("Investor name is missing");
  if (!tx.product) errors.push("Scheme product code is missing");
  if (!tx.sch_name) errors.push("Scheme name is missing");
  
  if (isNaN(tx.clos_bal)) {
    errors.push(`Invalid closing balance: "${tx.clos_bal}"`);
  }
  
  if (isNaN(tx.rupee_bal)) {
    errors.push(`Invalid rupee balance: "${tx.rupee_bal}"`);
  }
  
  if (isNaN(tx.rep_date.getTime())) {
    errors.push(`Invalid date format: "${tx.rep_date}"`);
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
    if (parts.length < 12) {
      this.totalErrors++;
      this.errors.push({
        line: trimmed,
        lineNumber: lineNum,
        reason: `Incorrect number of fields: expected at least 12, got ${parts.length}`
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

    // Convert parsed CSV line to the ParsedTransaction blueprint structure
    const clos_bal = parseDecimal(unitsStr);
    const rupee_bal = parseDecimal(amountStr);
    const rep_date = new Date(dateStr);

    const transaction = {
      clientPan: pan.toUpperCase(),
      investorName: name,
      folioNumber: folio,
      schemeCode,
      schemeName,
      fundHouse,
      category,
      transactionType: type.toUpperCase() as "BUY" | "SELL" | "SWITCH",
      units: clos_bal,
      nav: parseFloat(navStr),
      amount: rupee_bal,
      date: rep_date,

      foliochk: folio,
      inv_name: name,
      address1: "",
      address2: "",
      address3: "",
      city: "",
      pincode: "",
      product: schemeCode,
      sch_name: schemeName,
      rep_date,
      clos_bal,
      rupee_bal,
      pan_no: pan.toUpperCase(),
      joint1_pan: "",
      joint2_pan: "",
      guard_pan: "",
      email: "",
      mobile_no: "",
      bank_name: "",
      branch: "",
      ac_type: "",
      ac_no: "",
      ifsc_code: "",
      nom_name: "",
      relation: "",
      nom_percen: 0.0
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
