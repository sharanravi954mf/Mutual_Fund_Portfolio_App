class InvoiceMetadata {
  final String sourceFileName;
  final String? invoiceNumber;
  final String? invoiceReferenceNumber;
  final String? invoiceDate;
  final String? taxableValue;
  final String? igst;
  final String? cgst;
  final String? sgst;

  const InvoiceMetadata({
    required this.sourceFileName,
    this.invoiceNumber,
    this.invoiceReferenceNumber,
    this.invoiceDate,
    this.taxableValue,
    this.igst,
    this.cgst,
    this.sgst,
  });
}
