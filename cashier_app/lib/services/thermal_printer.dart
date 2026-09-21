import 'dart:io';
import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_printer/flutter_bluetooth_printer.dart'
    as fb;
import 'package:image/image.dart' as img;
import 'package:usb_serial/usb_serial.dart';

import '../models/transaction.dart';
import '../utils/format.dart';
import 'app_settings.dart';
import 'printer_permissions.dart';

/// The transport used to reach the thermal printer.
enum PrinterType { bluetooth, usb, network }

/// A pickable printer destination shown in the "Cetak" dialog.
class PrinterTarget {
  final PrinterType type;
  final String label;
  final String detail;

  /// Transport-specific handle:
  ///  - bluetooth: the printer MAC `address` (String)
  ///  - usb: a [UsbDevice]
  ///  - network: null (uses the stored host/port)
  final Object? handle;

  const PrinterTarget({
    required this.type,
    required this.label,
    required this.detail,
    this.handle,
  });
}

/// Unified thermal printing for BillFlow.
///
/// One receipt is rendered once into raw ESC/POS bytes (via the shared
/// [Generator]) and then sent over whichever transport the user selected:
///  - Bluetooth (bonded classic/RFCOMM) via [bt.BlueThermalPrinter]
///  - USB / kabel (serial CDC) via [usb_serial]
///  - Network (LAN TCP) via [NetworkPrinter] (the previously shipped path)
class ThermalPrinter {
  /// Renders [t] into raw ESC/POS bytes for a 58mm roll. Reused by every
  /// transport so the printed struk is always identical to the on-screen one.
  static Future<Uint8List> buildTicket(Transaction t) async {
    final profile = await CapabilityProfile.load(name: 'default');
    final gen = Generator(PaperSize.mm58, profile);
    final b = BytesBuilder();

    void emit(List<int> bytes) => b.add(bytes);

    final settings = AppSettings.instance;
    final method = paymentMethodByKey(t.paymentMethod);
    final isCash = method.key == 'cash';
    const hb = PosStyles(bold: true, align: PosAlign.center);
    // Compact body styles: the smallest thermally printable font is the
    // half-width Font B at size 1, so the "isi struk" (address, rows, totals,
    // payment and footer) is rendered dense and never cuts off the bottom.
    const center =
        PosStyles(fontType: PosFontType.fontB, align: PosAlign.center);
    const right =
        PosStyles(fontType: PosFontType.fontB, align: PosAlign.right);
    const bold =
        PosStyles(fontType: PosFontType.fontB, bold: true);
    const boldRight = PosStyles(
      fontType: PosFontType.fontB,
      bold: true,
      align: PosAlign.right,
    );
    // Store identity: bold, centered and double-width/double-height so the
    // shop name is the unmistakable head of the struk.
    const titleStyle = PosStyles(
      bold: true,
      align: PosAlign.center,
      width: PosTextSize.size2,
      height: PosTextSize.size2,
    );

    emit(gen.reset());
    // CP858 (PC858, Latin-1 with Euro sign) — named "CP858" in esc_pos_utils_plus
    // capabilities; the legacy alias "PC858" is not in the profile and throws.
    emit(gen.setGlobalCodeTable('CP858'));

    emit(await _emitLogo(gen, settings.storeLogoPath));
    // Blank line after the raster so print heads that don't advance past an
    // image start the title on a fresh row instead of swallowing it.
    emit(gen.emptyLines(1));

    final storeName =
        settings.storeName.isEmpty ? 'BillFlow' : settings.storeName;
    emit(gen.text(storeName, styles: titleStyle));
    // From here on the whole struk switches to the compact Font B (42 chars on
    // a 58mm roll) — the smallest and densest the printer supports.
    emit(gen.setGlobalFont(PosFontType.fontB));
    if (settings.storeAddress.isNotEmpty) {
      // Address sits centered under the title like the store name; it is
      // wrapped at the Font B line width and each line is centered.
      for (final line in _wrapLines(settings.storeAddress, 42)) {
        emit(gen.text(line, styles: center));
      }
    }
    if (settings.storePhone.isNotEmpty) {
      emit(gen.text('Telp: ${settings.storePhone}', styles: center));
    }
    emit(gen.hr());

    emit(gen.row([
      PosColumn(text: 'No. Bill', width: 6),
      PosColumn(
          text: t.billNumber ?? t.id.toString(),
          width: 6,
          styles: right),
    ]));
    emit(gen.row([
      PosColumn(text: 'Waktu', width: 6),
      PosColumn(
          text: formatDateTime(t.datetime),
          width: 6,
          styles: right),
    ]));
    emit(gen.row([
      PosColumn(text: 'Kasir', width: 6),
      PosColumn(
          text: settings.cashierName,
          width: 6,
          styles: right),
    ]));
    if (t.buyerName != null) {
      emit(gen.row([
        PosColumn(text: 'Pembeli', width: 6),
        PosColumn(
            text: t.buyerName!,
            width: 6,
            styles: right),
      ]));
    }
    emit(gen.row([
      PosColumn(text: 'Metode', width: 6),
      PosColumn(
          text: method.label,
          width: 6,
          styles: right),
    ]));

    // PPOB/PLN distinction is carried by the transaction data alone (nominal +
    // reference label below) — no "PAYMENT POINT" banner, so every struk shares
    // one clean, uniform layout.
    if (t.isBilling) {
      emit(gen.emptyLines(1));
      emit(gen.row([
        PosColumn(text: 'Jenis', width: 6),
        PosColumn(
            text: t.billingTypeDisplay,
            width: 6,
            styles: right),
      ]));
      emit(gen.row([
        PosColumn(
            text: t.billingReferenceLabel ?? 'No. Referensi', width: 6),
        PosColumn(
            text: t.billingReference ?? '-',
            width: 6,
            styles: right),
      ]));
    }

    emit(gen.hr());

    for (final item in t.items) {
      emit(gen.text(item.productName));
      emit(gen.row([
        PosColumn(
            text: '${item.quantity} x ${formatRupiah(item.price)}',
            width: 9),
        PosColumn(text: formatRupiah(item.subtotal), width: 3, styles: right),
      ]));
    }

    emit(gen.hr());

    emit(gen.row([
      PosColumn(
          text: t.isBilling ? 'Nominal Tagihan' : 'Subtotal',
          width: 6,
          styles: bold),
      PosColumn(
          text: formatRupiah(t.subtotal),
          width: 6,
          styles: boldRight),
    ]));
    if (t.adminFee > 0) {
      emit(gen.row([
        PosColumn(text: 'Biaya Admin', width: 6),
        PosColumn(
            text: formatRupiah(t.adminFee),
            width: 6,
            styles: right),
      ]));
    }
    if (t.extraAdmin > 0) {
      emit(gen.row([
        PosColumn(text: 'Admin Tambahan', width: 6),
        PosColumn(
            text: formatRupiah(t.extraAdmin),
            width: 6,
            styles: right),
      ]));
    }
    if (t.billingFine > 0) {
      emit(gen.row([
        PosColumn(text: 'Biaya Denda', width: 6),
        PosColumn(
            text: formatRupiah(t.billingFine),
            width: 6,
            styles: right),
      ]));
    }
    if (t.discount > 0) {
      emit(gen.row([
        PosColumn(text: t.discountLabel ?? 'Diskon', width: 6),
        PosColumn(
            text: '- ${formatRupiah(t.discount)}',
            width: 6,
            styles: right),
      ]));
    }
    emit(gen.row([
      PosColumn(
          text: 'GRAND TOTAL', width: 6, styles: bold),
      PosColumn(
          text: formatRupiah(t.total),
          width: 6,
          styles: boldRight),
    ]));

    emit(gen.hr());

    if (isCash) {
      emit(gen.row([
        PosColumn(text: 'Tunai Bayar', width: 6),
        PosColumn(
            text: formatRupiah(t.cashReceived),
            width: 6,
            styles: right),
      ]));
      emit(gen.row([
        PosColumn(
            text: 'Kembalian', width: 6, styles: bold),
        PosColumn(
            text: formatRupiah(t.change),
            width: 6,
            styles: boldRight),
      ]));
    } else {
      emit(gen.row([
        PosColumn(
            text: 'Total Bayar', width: 6, styles: bold),
        PosColumn(
            text: formatRupiah(t.total),
            width: 6,
            styles: boldRight),
      ]));
    }
    if (t.paymentDetail != null && t.paymentDetail!.isNotEmpty) {
      emit(gen.text('Detail: ${t.paymentDetail}'));
    }

    emit(gen.emptyLines(1));
    emit(gen.text('TERIMA KASIH TELAH BERBELANJA', styles: hb));
    emit(gen.text('Simpan struk ini sebagai bukti pembayaran yang sah.',
        styles: center));
    emit(gen.text('Powered by BillFlow POS', styles: center));
    if (settings.storeFooter.isNotEmpty) {
      emit(gen.hr());
      emit(gen.text(settings.storeFooter, styles: center));
    }
    emit(gen.emptyLines(3));
    emit(gen.cut());

    return b.toBytes();
  }

/// Renders the configured store logo (if any) as an ESC/POS bit-image sized to
/// the full printable width of a 58mm roll (384 dots, double density) and
/// placed at the very top of the struk, above the store name.
///
/// Failures are contained so a missing/broken image never crashes printing —
/// the text-only struk still comes out — but are logged for debugging.
static Future<List<int>> _emitLogo(Generator gen, String logoPath) async {
  if (logoPath.isEmpty) return const [];

  Uint8List raw;
  try {
    raw = logoPath == AppSettings.builtinLogoMarker
        ? (await rootBundle.load('assets/logo/Logo BillFlow.jpg'))
            .buffer
            .asUint8List()
        : await File(logoPath).readAsBytes();
  } catch (e) {
    debugPrint('LOGO: gagal membaca file: $e');
    return const [];
  }

  try {
    final decoded = img.decodeImage(raw);
    if (decoded == null) {
      debugPrint('LOGO: format gambar tidak dikenal');
      return const [];
    }
    // 58mm roll ≈ 384 printable dots — resize to the full width so the logo
    // matches the paper exactly (the ESC/POS encoder slices it into columns).
    final resized = img.copyResize(decoded,
        width: 384,
        height: (decoded.height * 384 / decoded.width).round(),
        interpolation: img.Interpolation.linear);
    return gen.image(resized);
  } catch (e) {
    debugPrint('LOGO: gagal mengolah gambar: $e');
    return const [];
  }
}

  /// Prints [t] to the printer described by [target].
  /// Returns null on success or a human-readable error message.
  static Future<String?> print(Transaction t, PrinterTarget target) async {
    Uint8List bytes;
    try {
      bytes = await buildTicket(t);
    } catch (e, stack) {
      debugPrint('PRINT ERROR (buildTicket): $e\n$stack');
      return 'Gagal menyusun data cetak: $e';
    }
    try {
      final error = switch (target.type) {
        PrinterType.bluetooth => _printBluetooth(bytes, target),
        PrinterType.usb => _printUsb(bytes, target),
        PrinterType.network => _printNetwork(bytes),
      };
      final result = await error;
      if (result != null) debugPrint('PRINT ERROR: $result');
      return result;
    } catch (e, stack) {
      debugPrint('PRINT ERROR: $e\n$stack');
      return 'Gagal mencetak: $e';
    }
  }

  static Future<String?> _printBluetooth(
      Uint8List bytes, PrinterTarget target) async {
    final address = (target.handle as String?) ?? '';
    final label = target.label;

    // 3) Validate the destination before touching the socket layer.
    if (address.isEmpty) {
      const msg =
          'Alamat (MAC) printer Bluetooth kosong. Pilih ulang printer dahulu.';
      debugPrint('PRINT ERROR: $msg');
      return msg;
    }
    if (!await isBluetoothEnabled()) {
      const msg =
          'Bluetooth dalam keadaan mati. Nyalakan Bluetooth terlebih dahulu.';
      debugPrint('PRINT ERROR: $msg');
      return msg;
    }

    try {
      // 1) Open an RFCOMM socket to the chosen printer first and confirm the
      //    connection is actually established before any print bytes are sent.
      //    The printer is bonded, so discovery emits it immediately and this
      //    returns within a second.
      final connected = await fb.FlutterBluetoothPrinter.connect(address);
      if (!connected) {
        final msg = 'Gagal terhubung ke printer "$label". Pastikan printer '
            'menyala dan berada dalam jangkauan, lalu coba lagi.';
        debugPrint('PRINT ERROR: $msg (address=$address)');
        return msg;
      }

      // 2) Send in small chunks with a pause between each. The Android side of
      //    this plugin ignores maxBufferSize/delayTime and issues ONE
      //    writeStream.write(data) + flush() for whatever byte array it is
      //    given. A logo resized to the full 384-dot width turns a struk into
      //    a ~10KB burst, which overflows the tiny receive buffer of budget
      //    58mm printers and silently drops every byte beyond it — the symptom
      //    being "only the logo prints". Chunking keeps each write well under
      //    that buffer and lets the printer drain between chunks.
      const chunkSize = 512;
      const chunkDelay = Duration(milliseconds: 100);
      final data = bytes;
      for (var offset = 0; offset < data.length; offset += chunkSize) {
        var end = offset + chunkSize;
        if (end > data.length) end = data.length;
        final ok = await fb.FlutterBluetoothPrinter.printBytes(
          address: address,
          data: data.sublist(offset, end),
          keepConnected: true,
        );
        if (!ok) {
          const msg =
              'Gagal mengirim data cetak ke printer (dibalas false oleh '
              'plugin Bluetooth).';
          debugPrint('PRINT ERROR: $msg (address=$address)');
          try {
            await fb.FlutterBluetoothPrinter.disconnect(address);
          } catch (_) {}
          return msg;
        }
        // Give the printer time to consume the chunk before the next one.
        await Future.delayed(chunkDelay);
      }

      // Let the printer drain its input buffer before the link is torn down;
      // a too-early close is what hangs the buffer on cheap devices.
      await Future.delayed(const Duration(milliseconds: 800));

      // 4) Clean disconnect so the next print starts from a fresh socket.
      await fb.FlutterBluetoothPrinter.disconnect(address);
      return null;
    } catch (e, stack) {
      debugPrint('PRINT ERROR: $e\n$stack');
      try {
        await fb.FlutterBluetoothPrinter.disconnect(address);
      } catch (_) {}
      return 'Gagal mencetak ke printer "$label": $e';
    }
  }

  static Future<String?> _printUsb(Uint8List bytes, PrinterTarget target) {
    final device = target.handle as UsbDevice;
    return _sendUsb(device, bytes);
  }

  static Future<String?> _sendUsb(UsbDevice device, Uint8List bytes) async {
    UsbPort? port;
    try {
      port = await device.create();
      if (port == null) {
        return 'Gagal membuka port USB "${device.deviceName}".';
      }
      final ok = await port.open();
      if (!ok) {
        return 'Gagal membuka port USB (izin USB ditolak?).';
      }
      await port.setPortParameters(
          9600, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);
      // Chunked send: the logo raster makes a struk several KB, and a budget
      // printer only buffers a few KB. Smaller, spaced writes let it keep up
      // instead of silently dropping the end of the struk.
      const chunkSize = 256;
      const chunkDelay = Duration(milliseconds: 100);
      for (var offset = 0; offset < bytes.length; offset += chunkSize) {
        var end = offset + chunkSize;
        if (end > bytes.length) end = bytes.length;
        await port.write(bytes.sublist(offset, end));
        await Future.delayed(chunkDelay);
      }
      await Future.delayed(const Duration(milliseconds: 200));
      await port.close();
      return null;
    } catch (e) {
      try {
        await port?.close();
      } catch (_) {}
      return 'Gagal mencetak USB: $e';
    }
  }

  static Future<String?> _printNetwork(Uint8List bytes) async {
    final settings = AppSettings.instance;
    if (settings.printerHost.isEmpty) {
      return 'Alamat printer jaringan belum diatur.';
    }
    Socket? socket;
    try {
      socket = await Socket.connect(settings.printerHost, settings.printerPort,
          timeout: const Duration(seconds: 6));
      // Chunked send with pauses — same reasoning as the Bluetooth path: a
      // full-width logo raster is a multi-KB struct and cheap LAN adapters
      // forward it to the printer over a slow serial link with a tiny buffer.
      const chunkSize = 512;
      const chunkDelay = Duration(milliseconds: 100);
      for (var offset = 0; offset < bytes.length; offset += chunkSize) {
        var end = offset + chunkSize;
        if (end > bytes.length) end = bytes.length;
        socket.add(bytes.sublist(offset, end));
        await socket.flush();
        await Future.delayed(chunkDelay);
      }
      await Future.delayed(const Duration(milliseconds: 200));
      socket.destroy();
      return null;
    } catch (e) {
      try {
        socket?.destroy();
      } catch (_) {}
      return 'Gagal mencetak jaringan: $e';
    }
  }
}

/// Wraps [text] into lines of at most [maxChars] columns, splitting at word
/// boundaries so each wrapped line can be centered (used for the store address
/// and other free-flowing header text).
List<String> _wrapLines(String text, int maxChars) {
  final words = text.trim().split(RegExp(r'\s+'));
  if (words.isEmpty) return const [];

  final lines = <String>[];
  var cur = <String>[];
  var len = 0;

  for (final w in words) {
    if (len == 0) {
      cur.add(w);
      len = w.length;
    } else if (len + 1 + w.length <= maxChars) {
      cur.add(w);
      len += 1 + w.length;
    } else {
      lines.add(cur.join(' '));
      cur = [w];
      len = w.length;
    }
  }
  if (cur.isNotEmpty) lines.add(cur.join(' '));
  return lines;
}
