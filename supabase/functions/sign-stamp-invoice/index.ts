import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { PDFDocument } from "npm:pdf-lib@1.17.1";
import * as zip from "npm:@zip.js/zip.js";
import { encode as base64Encode } from "https://deno.land/std@0.177.0/encoding/base64.ts";

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

async function signSinglePdf(
  pdfBytes: Uint8Array,
  signaturePngBytes: Uint8Array,
  stampPngBytes: Uint8Array,
  stampX: number,
  stampY: number,
  sigX: number,
  sigY: number,
  stampW: number,
  stampH: number,
  sigW: number,
  sigH: number
): Promise<Uint8Array> {
  const pdfDoc = await PDFDocument.load(pdfBytes);
  const pages = pdfDoc.getPages();
  if (pages.length === 0) {
    throw new Error("PDF document has 0 pages.");
  }
  
  const lastPage = pages[pages.length - 1];
  
  const signatureImage = await pdfDoc.embedPng(signaturePngBytes);
  const stampImage = await pdfDoc.embedPng(stampPngBytes);

  lastPage.drawImage(stampImage, {
    x: Number(stampX),
    y: Number(stampY),
    width: Number(stampW),
    height: Number(stampH),
  });

  lastPage.drawImage(signatureImage, {
    x: Number(sigX),
    y: Number(sigY),
    width: Number(sigW),
    height: Number(sigH),
  });

  return await pdfDoc.save();
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: corsHeaders });
  }

  try {
    const {
      invoicePdf,      
      invoiceFile,     
      signaturePng,    
      stampPng,        
      stampX = 400,
      stampY = 102,
      sigX = 420,
      sigY = 72,
      stampW = 120,
      stampH = 60,
      sigW = 120,
      sigH = 50,
      url,
      action,          
    } = await req.json();

    if (action === "proxy-get") {
      if (!url) {
        return new Response(
          JSON.stringify({ error: "Missing target url for proxy" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
      console.log(`Proxying GET request for URL: ${url}`);
      const res = await fetch(url);
      const resText = await res.text();
      return new Response(resText, {
        headers: { 
          ...corsHeaders, 
          "Content-Type": "application/json" 
        }
      });
    }

    const fileBase64 = invoiceFile || invoicePdf;

    if (!fileBase64) {
      return new Response(
        JSON.stringify({ error: "Missing required files (PDF/ZIP)" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const fileBytes = base64ToUint8Array(fileBase64);

    if (action === "decrypt") {
      const zipReader = new zip.ZipReader(
        new zip.Uint8ArrayReader(fileBytes),
        { password: Deno.env.get("RTA_DECRYPTION_PASSWORD") || "cams123" }
      );
      const entries = await zipReader.getEntries();
      
      const pdfEntries = entries.filter(entry => {
        const lowerName = entry.filename.toLowerCase();
        return lowerName.endsWith(".pdf") && 
               !lowerName.includes("__macosx") && 
               !entry.filename.split("/").pop()?.startsWith("._");
      });

      console.log(`Found ${pdfEntries.length} PDFs in CAMS archive.`);

      const files = await Promise.all(pdfEntries.map(async (entry) => {
        const writer = new zip.Uint8ArrayWriter();
        const rawPdfBytes = await (entry as any).getData(writer);
        const base64Content = base64Encode(rawPdfBytes);
        return { name: entry.filename, content: base64Content };
      }));

      return new Response(JSON.stringify({ files }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" }
      });
    }

    if (!signaturePng || !stampPng) {
      return new Response(
        JSON.stringify({ error: "Missing signature or stamp overlay files" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const signaturePngBytes = base64ToUint8Array(signaturePng);
    const stampPngBytes = base64ToUint8Array(stampPng);

    const isZip = fileBytes.length > 4 && 
                  fileBytes[0] === 0x50 && 
                  fileBytes[1] === 0x4B && 
                  fileBytes[2] === 0x03 && 
                  fileBytes[3] === 0x04;

    if (isZip) {
      const zipReader = new zip.ZipReader(
        new zip.Uint8ArrayReader(fileBytes),
        { password: Deno.env.get("RTA_DECRYPTION_PASSWORD") || "cams123" }
      );
      const entries = await zipReader.getEntries();
      const zipWriter = new zip.ZipWriter(new zip.Uint8ArrayWriter());
      
      const pdfEntries = entries.filter(entry => {
        const lowerName = entry.filename.toLowerCase();
        return lowerName.endsWith(".pdf") && 
               !lowerName.includes("__macosx") && 
               !entry.filename.split("/").pop()?.startsWith("._");
      });

      const results = [];
      for (const entry of pdfEntries) {
        try {
          const writer = new zip.Uint8ArrayWriter();
          const rawPdfBytes = await (entry as any).getData(writer);
          const signedPdfBytes = await signSinglePdf(
            rawPdfBytes, 
            signaturePngBytes, 
            stampPngBytes, 
            stampX, 
            stampY, 
            sigX, 
            sigY,
            stampW,
            stampH,
            sigW,
            sigH
          );
          results.push({ filename: entry.filename, bytes: signedPdfBytes, success: true });
        } catch (err) {
          console.error(`Failed to process PDF entry ${entry.filename}:`, err);
          results.push({ filename: entry.filename, bytes: null, success: false, entry });
        }
      }

      for (const res of results) {
        if (res.success && res.bytes) {
          await zipWriter.add(res.filename, new zip.Uint8ArrayReader(res.bytes));
        } else {
          const entry = (res as any).entry;
          if (entry) {
            const writer = new zip.Uint8ArrayWriter();
            const rawPdfBytes = await entry.getData(writer);
            await zipWriter.add(res.filename, new zip.Uint8ArrayReader(rawPdfBytes));
          }
        }
      }

      for (const entry of entries) {
        const lowerName = entry.filename.toLowerCase();
        const isPdf = lowerName.endsWith(".pdf") && 
                      !lowerName.includes("__macosx") && 
                      !entry.filename.split("/").pop()?.startsWith("._");
        if (!isPdf && !entry.directory) {
          const writer = new zip.Uint8ArrayWriter();
          const otherBytes = await (entry as any).getData(writer);
          await zipWriter.add(entry.filename, new zip.Uint8ArrayReader(otherBytes));
        }
      }

      const outputZipBytes = await zipWriter.close();
      const base64Zip = base64Encode(outputZipBytes.buffer as ArrayBuffer);
      return new Response(JSON.stringify({ signedPdf: base64Zip }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });

    } else {
      console.log("Single PDF detected. Overlaying signature and stamp...");
      const signedPdfBytes = await signSinglePdf(
        fileBytes, 
        signaturePngBytes, 
        stampPngBytes, 
        stampX, 
        stampY, 
        sigX, 
        sigY,
        stampW,
        stampH,
        sigW,
        sigH
      );

      const base64Pdf = base64Encode(signedPdfBytes.buffer as ArrayBuffer);
      return new Response(JSON.stringify({ signedPdf: base64Pdf }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

  } catch (err) {
    console.error("PDF Signer batch processing failed:", err);
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : String(err) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
