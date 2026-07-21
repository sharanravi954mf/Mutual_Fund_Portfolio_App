import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import * as zip from "npm:@zip.js/zip.js";
import * as XLSX from "npm:xlsx";
import { extractText, getDocumentProxy } from "npm:unpdf";
import { encode as base64Encode } from "https://deno.land/std@0.177.0/encoding/base64.ts";
import { requireAdvisor } from "../_shared/authorization.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function base64ToUint8Array(base64: string): Uint8Array {
  const binaryString = atob(base64.replace(/\s/g, ""));
  const bytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  return bytes;
}

function getRowValue(row: Record<string, any>, searchKeys: string[]): any {
  for (const k of searchKeys) {
    if (row[k] !== undefined) return row[k];
    const cleanSearch = k.toLowerCase().replace(/[^a-z0-9]/g, "");
    const matchKey = Object.keys(row).find(rk => {
      return rk.toLowerCase().replace(/[^a-z0-9]/g, "") === cleanSearch;
    });
    if (matchKey !== undefined) return row[matchKey];
  }
  return null;
}

function setRowValue(row: Record<string, any>, searchKeys: string[], value: any): void {
  for (const k of searchKeys) {
    if (row[k] !== undefined) {
      row[k] = value;
      return;
    }
    const cleanSearch = k.toLowerCase().replace(/[^a-z0-9]/g, "");
    const matchKey = Object.keys(row).find(rk => {
      return rk.toLowerCase().replace(/[^a-z0-9]/g, "") === cleanSearch;
    });
    if (matchKey !== undefined) {
      row[matchKey] = value;
      return;
    }
  }
  row[searchKeys[0]] = value;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: corsHeaders });
  }

  const authorization = await requireAdvisor(req);
  if ("failure" in authorization) {
    return new Response(
      JSON.stringify({ error: authorization.failure.message }),
      {
        status: authorization.failure.status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  try {
    const { excelFile, zipFile } = await req.json();

    if (!excelFile || !zipFile) {
      return new Response(
        JSON.stringify({ error: "Missing excelFile or zipFile parameters" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    console.log("Decoding base64 inputs...");
    const excelBytes = base64ToUint8Array(excelFile);
    const zipBytes = base64ToUint8Array(zipFile);

    // 1. Read Excel file
    console.log("Parsing Excel workbook...");
    const workbook = XLSX.read(excelBytes, { type: "array" });
    const sheetName = workbook.SheetNames[0];
    const worksheet = workbook.Sheets[sheetName];
    const jsonRows = XLSX.utils.sheet_to_json(worksheet, { defval: "" }) as any[];
    console.log(`Loaded ${jsonRows.length} rows from Excel sheet.`);

    // 2. Unzip or parse PDF files
    const pdfFiles: Array<{ filename: string; text: string }> = [];
    const isZip = zipBytes.length > 4 && 
                  zipBytes[0] === 0x50 && 
                  zipBytes[1] === 0x4B && 
                  zipBytes[2] === 0x03 && 
                  zipBytes[3] === 0x04;

    if (isZip) {
      console.log("Decompressing ZIP archive...");
      const zipReader = new zip.ZipReader(
        new zip.Uint8ArrayReader(zipBytes),
        { password: "cams123" }
      );
      const entries = await zipReader.getEntries();
      
      const pdfEntries = entries.filter(entry => {
        const lowerName = entry.filename.toLowerCase();
        return lowerName.endsWith(".pdf") && 
               !lowerName.includes("__macosx") && 
               !entry.filename.split("/").pop()?.startsWith("._");
      });

      console.log(`Found ${pdfEntries.length} PDFs to extract text from.`);

      for (const entry of pdfEntries) {
        try {
          const writer = new zip.Uint8ArrayWriter();
          const rawPdfBytes = await (entry as any).getData(writer);
          const pdfDoc = await getDocumentProxy(rawPdfBytes);
          const { text } = await extractText(pdfDoc);
          const fullText = text ? text.join("\n") : "";

          pdfFiles.push({
            filename: entry.filename.split("/").pop() || entry.filename,
            text: fullText,
          });
        } catch (err) {
          console.error(`Failed to parse text from PDF ${entry.filename}:`, err);
        }
      }
    } else {
      console.log("Single PDF file uploaded. Parsing directly...");
      try {
        const pdfDoc = await getDocumentProxy(zipBytes);
        const { text } = await extractText(pdfDoc);
        const fullText = text ? text.join("\n") : "";
        pdfFiles.push({
          filename: "Uploaded_Invoice.pdf",
          text: fullText,
        });
      } catch (err) {
        console.error(`Failed to parse text from single PDF:`, err);
      }
    }

    console.log(`Successfully extracted text from ${pdfFiles.length} PDFs.`);

    // 3. Match PDFs to Excel rows and update fields
    let updatedCount = 0;
    for (const pdfFile of pdfFiles) {
      const text = pdfFile.text;
      const textLower = text.toLowerCase();
      
      let bestRowIndex = -1;
      let highestScore = 0;
      
      for (let i = 0; i < jsonRows.length; i++) {
        const row = jsonRows[i];
        let score = 0;
        
        // GSTR Match
        const gstr = getRowValue(row, ["amc gstr number", "gstr number", "gstin", "amcgstrnumber"]);
        if (gstr && textLower.includes(String(gstr).toLowerCase().trim())) {
          score += 100;
        }
        
        // Invoice Reference No Match
        const refNo = getRowValue(row, ["invoice reference no", "invoice ref no", "ref no", "invoicereferenceno"]);
        if (refNo && textLower.includes(String(refNo).toLowerCase().trim())) {
          score += 100;
        }
        
        // AMC Name Match
        const amc = getRowValue(row, ["amc", "amc name", "fund house"]);
        if (amc) {
          const amcParts = String(amc).toLowerCase().split(/\s+/).filter(p => p.length > 2);
          let amcMatchCount = 0;
          for (const part of amcParts) {
            if (textLower.includes(part)) {
              amcMatchCount++;
            }
          }
          if (amcMatchCount > 0) {
            score += amcMatchCount * 15;
          }
          if (pdfFile.filename.toLowerCase().includes(String(amc).toLowerCase().trim())) {
            score += 40;
          }
        }
        
        // Fund Code Match
        const fundCode = getRowValue(row, ["fund code", "fundcode"]);
        if (fundCode && textLower.includes(String(fundCode).toLowerCase().trim())) {
          score += 30;
        }

        // Taxable Income Match
        const taxable = getRowValue(row, ["taxable income", "taxable income amt", "taxable amt"]);
        if (taxable && textLower.includes(String(taxable).toLowerCase().trim())) {
          score += 15;
        }
        
        // GST Amt Match
        const gstAmt = getRowValue(row, ["gst amt", "gst amount", "gstamt"]);
        if (gstAmt && textLower.includes(String(gstAmt).toLowerCase().trim())) {
          score += 15;
        }
        
        if (score > highestScore) {
          highestScore = score;
          bestRowIndex = i;
        }
      }
      
      if (bestRowIndex !== -1 && highestScore >= 25) {
        const row = jsonRows[bestRowIndex];
        
        // Extract Invoice No (Standard CAMS format regex)
        const invNoMatch = text.match(/(?:invoice|inv|bill)\s*(?:no|number|ref\s*no)?\.?\s*[:\-\s]\s*([a-zA-Z0-9/\-_]+)/i);
        const invoiceNo = invNoMatch ? invNoMatch[1].trim() : "";
        
        // Extract Invoice Date
        const dateMatch = text.match(/(?:invoice|inv|bill)?\s*date\s*[:\-\s]\s*([0-9]{2}[/\.\-\s][0-9]{2}[/\.\-\s][0-9]{4}|[0-9]{2}[/\.\-\s][a-zA-Z]{3}[/\.\-\s][0-9]{4})/i);
        const invoiceDate = dateMatch ? dateMatch[1].trim() : "";
        
        setRowValue(row, ["invoice no", "invoiceno", "invoice number"], invoiceNo);
        setRowValue(row, ["invoice date", "invoicedate"], invoiceDate);
        setRowValue(row, ["file name", "filename"], pdfFile.filename);
        updatedCount++;
      }
    }

    console.log(`Updated ${updatedCount} rows in Excel dataset.`);

    // 4. Write back to workbook
    const newWorksheet = XLSX.utils.json_to_sheet(jsonRows);
    workbook.Sheets[sheetName] = newWorksheet;
    const outputBytes = XLSX.write(workbook, { type: "array", bookType: "xlsx" });

    const base64Excel = base64Encode((outputBytes as Uint8Array).buffer as ArrayBuffer);

    return new Response(JSON.stringify({ updatedExcel: base64Excel, updatedCount }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    });

  } catch (err) {
    console.error("Excel update failed:", err);
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : String(err) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
