import UIKit

/// Renders a printable, DMV-style driving log (US Letter) with a summary, a running-total table and
/// a signature block.
@MainActor
enum PDFLogRenderer {
    private static let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
    private static let margin: CGFloat = 36
    private static let rowHeight: CGFloat = 26
    private static let headerRowHeight: CGFloat = 22
    private static let footerHeight: CGFloat = 28
    private static let signatureBlockHeight: CGFloat = 150

    private struct Column {
        let title: String
        let width: CGFloat
        let alignment: NSTextAlignment
    }

    private static let columns: [Column] = [
        Column(title: "#", width: 24, alignment: .center),
        Column(title: "Date", width: 62, alignment: .left),
        Column(title: "Time", width: 90, alignment: .left),
        Column(title: "Hours", width: 40, alignment: .right),
        Column(title: "Night", width: 40, alignment: .right),
        Column(title: "Total", width: 44, alignment: .right),
        Column(title: "Dist.", width: 42, alignment: .right),
        Column(title: "Supervisor", width: 82, alignment: .left),
        Column(title: "Conditions / Notes", width: 116, alignment: .left),
    ]

    private static let accent = UIColor(red: 47 / 255, green: 107 / 255, blue: 1, alpha: 1)
    private static let ink = UIColor(white: 0.12, alpha: 1)
    private static let muted = UIColor(white: 0.42, alpha: 1)
    private static let rule = UIColor(white: 0.82, alpha: 1)
    private static let stripe = UIColor(red: 0.95, green: 0.96, blue: 1, alpha: 1)

    static func render(drives: [Drive], settings: AppSettings, stats: LogStats) -> Data? {
        let ordered = drives.sorted { $0.startDate < $1.startDate }
        let unit = settings.distanceUnit

        // Layout: page 1 has the summary; later pages are table only; the last page also needs room
        // for the signature block.
        let firstPageTableTop: CGFloat = 262
        let otherPageTableTop: CGFloat = margin + 34
        let tableBottom = pageRect.height - margin - footerHeight
        let rowsFirst = max(1, Int((tableBottom - firstPageTableTop - headerRowHeight) / rowHeight))
        let rowsOther = max(1, Int((tableBottom - otherPageTableTop - headerRowHeight) / rowHeight))

        var pages: [[Int]] = []
        var index = 0
        repeat {
            let capacity = pages.isEmpty ? rowsFirst : rowsOther
            let end = min(ordered.count, index + capacity)
            pages.append(Array(index..<end))
            index = end
        } while index < ordered.count

        // The totals row goes under the last page's rows, so a full last page pushes its final row over.
        let lastCapacity = pages.count == 1 ? rowsFirst : rowsOther
        if pages[pages.count - 1].count >= lastCapacity, let moved = pages[pages.count - 1].popLast() {
            pages.append([moved])
        }

        // Make sure the signature block fits under the last page's rows.
        let lastTop = pages.count == 1 ? firstPageTableTop : otherPageTableTop
        let lastRowsBottom = lastTop + headerRowHeight + CGFloat(pages[pages.count - 1].count) * rowHeight + rowHeight
        let needsSignaturePage = lastRowsBottom + signatureBlockHeight > tableBottom
        let pageCount = pages.count + (needsSignaturePage ? 1 : 0)

        var cumulative = [Double](repeating: 0, count: ordered.count)
        var running = 0.0
        for (i, d) in ordered.enumerated() {
            running += d.totalMinutes
            cumulative[i] = running
        }

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "Supervised Driving Log",
            kCGPDFContextCreator as String: "TrackMyDrive",
            kCGPDFContextAuthor as String: settings.studentName,
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        return renderer.pdfData { ctx in
            for (pageIndex, rows) in pages.enumerated() {
                ctx.beginPage()
                var y: CGFloat
                if pageIndex == 0 {
                    drawSummary(settings: settings, stats: stats, unit: unit)
                    y = firstPageTableTop
                } else {
                    draw("Supervised Driving Log (continued)", at: CGPoint(x: margin, y: margin),
                         font: .systemFont(ofSize: 13, weight: .semibold), color: ink)
                    y = otherPageTableTop
                }
                y = drawTableHeader(at: y)
                for (rowOffset, i) in rows.enumerated() {
                    drawRow(ordered[i], number: i + 1, cumulativeMinutes: cumulative[i], unit: unit,
                            y: y, striped: rowOffset % 2 == 1)
                    y += rowHeight
                }
                if ordered.isEmpty {
                    draw("No drives logged yet.", in: CGRect(x: margin, y: y + 6, width: pageRect.width - 2 * margin, height: 16),
                         font: .italicSystemFont(ofSize: 10), color: muted, alignment: .center)
                    y += rowHeight
                }
                if pageIndex == pages.count - 1 {
                    y = drawTotalsRow(stats: stats, unit: unit, y: y)
                    if !needsSignaturePage { drawSignatureBlock(top: y + 18) }
                }
                drawFooter(page: pageIndex + 1, of: pageCount)
            }
            if needsSignaturePage {
                ctx.beginPage()
                draw("Supervised Driving Log — Certification", at: CGPoint(x: margin, y: margin),
                     font: .systemFont(ofSize: 13, weight: .semibold), color: ink)
                drawSignatureBlock(top: margin + 40)
                drawFooter(page: pageCount, of: pageCount)
            }
        }
    }

    // MARK: Sections

    private static func drawSummary(settings: AppSettings, stats: LogStats, unit: DistanceUnit) {
        let width = pageRect.width - 2 * margin
        draw("Supervised Driving Log", at: CGPoint(x: margin, y: margin),
             font: .systemFont(ofSize: 24, weight: .bold), color: ink)
        draw("Generated by TrackMyDrive on \(Fmt.dateTime.string(from: Date()))", at: CGPoint(x: margin, y: margin + 32),
             font: .systemFont(ofSize: 9), color: muted)

        // Driver details
        let details: [(String, String)] = [
            ("Driver", settings.studentName.isEmpty ? "________________________" : settings.studentName),
            ("Permit #", settings.permitNumber.isEmpty ? "______________" : settings.permitNumber),
            ("State", settings.statePreset?.name ?? (settings.stateCode.isEmpty ? "—" : settings.stateCode)),
        ]
        var x = margin
        let detailWidths: [CGFloat] = [width * 0.45, width * 0.33, width * 0.22]
        for (i, item) in details.enumerated() {
            draw(item.0.uppercased(), at: CGPoint(x: x, y: margin + 54), font: .systemFont(ofSize: 8, weight: .semibold), color: muted)
            draw(item.1, in: CGRect(x: x, y: margin + 66, width: detailWidths[i] - 8, height: 18),
                 font: .systemFont(ofSize: 13, weight: .medium), color: ink, alignment: .left)
            x += detailWidths[i]
        }

        // Stat cards
        let cards: [(String, String, String)] = [
            ("TOTAL HOURS", Fmt.hours(minutes: stats.totalMinutes), "Goal \(Fmt.hoursShort(minutes: settings.totalGoalMinutes)) · \(Int((stats.totalProgress * 100).rounded()))%"),
            ("NIGHT HOURS", Fmt.hours(minutes: stats.nightMinutes), "Goal \(Fmt.hoursShort(minutes: settings.nightGoalMinutes)) · \(Int((stats.nightProgress * 100).rounded()))%"),
            ("DAY HOURS", Fmt.hours(minutes: stats.dayMinutes), "\(stats.driveCount) drive\(stats.driveCount == 1 ? "" : "s")"),
            stats.hasWeatherGoal
                ? ("BAD WEATHER", Fmt.hours(minutes: stats.adverseWeatherMinutes), "Goal \(Fmt.hoursShort(minutes: settings.weatherGoalMinutes)) · \(Int((stats.weatherProgress * 100).rounded()))%")
                : ("DISTANCE", String(format: "%.0f", unit.value(fromMeters: stats.distanceMeters)), unit.label.lowercased()),
        ]
        let gap: CGFloat = 10
        let cardWidth = (width - gap * 3) / 4
        let cardTop = margin + 100
        for (i, card) in cards.enumerated() {
            let rect = CGRect(x: margin + CGFloat(i) * (cardWidth + gap), y: cardTop, width: cardWidth, height: 76)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 10)
            stripe.setFill()
            path.fill()
            draw(card.0, at: CGPoint(x: rect.minX + 10, y: rect.minY + 9), font: .systemFont(ofSize: 7.5, weight: .bold), color: accent)
            draw(card.1, in: CGRect(x: rect.minX + 10, y: rect.minY + 22, width: rect.width - 20, height: 30),
                 font: .monospacedDigitSystemFont(ofSize: 22, weight: .bold), color: ink, alignment: .left)
            draw(card.2, in: CGRect(x: rect.minX + 10, y: rect.minY + 54, width: rect.width - 20, height: 14),
                 font: .systemFont(ofSize: 8.5), color: muted, alignment: .left)
        }

        // Progress bar for the main goal
        let barRect = CGRect(x: margin, y: cardTop + 90, width: width, height: 8)
        UIColor(white: 0.9, alpha: 1).setFill()
        UIBezierPath(roundedRect: barRect, cornerRadius: 4).fill()
        accent.setFill()
        let filled = CGRect(x: barRect.minX, y: barRect.minY, width: max(8, barRect.width * stats.totalProgress), height: barRect.height)
        if stats.totalProgress > 0 { UIBezierPath(roundedRect: filled, cornerRadius: 4).fill() }
    }

    @discardableResult
    private static func drawTableHeader(at y: CGFloat) -> CGFloat {
        let rect = CGRect(x: margin, y: y, width: pageRect.width - 2 * margin, height: headerRowHeight)
        accent.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 5).fill()
        var x = margin
        for col in columns {
            draw(col.title, in: CGRect(x: x + 4, y: y + 5.5, width: col.width - 8, height: 12),
                 font: .systemFont(ofSize: 8.5, weight: .bold), color: .white, alignment: col.alignment)
            x += col.width
        }
        return y + headerRowHeight
    }

    private static func drawRow(_ d: Drive, number: Int, cumulativeMinutes: Double, unit: DistanceUnit,
                                y: CGFloat, striped: Bool) {
        let width = pageRect.width - 2 * margin
        if striped {
            stripe.setFill()
            UIRectFill(CGRect(x: margin, y: y, width: width, height: rowHeight))
        }
        rule.setFill()
        UIRectFill(CGRect(x: margin, y: y + rowHeight - 0.5, width: width, height: 0.5))

        var notes = Fmt.conditions(d)
        if !d.notes.isEmpty {
            notes += (notes.isEmpty ? "" : " · ") + d.notes.replacingOccurrences(of: "\n", with: " ")
        }
        let values = [
            "\(number)",
            Fmt.shortDate.string(from: d.startDate),
            "\(Fmt.time.string(from: d.startDate))–\(Fmt.time.string(from: d.endDate))",
            Fmt.hours(minutes: d.totalMinutes),
            Fmt.hours(minutes: d.clampedNightMinutes),
            Fmt.hours(minutes: cumulativeMinutes),
            d.distanceMeters.map { String(format: "%.1f", unit.value(fromMeters: $0)) } ?? "—",
            d.supervisor.isEmpty ? "—" : d.supervisor,
            notes.isEmpty ? "—" : notes,
        ]
        var x = margin
        for (i, col) in columns.enumerated() {
            let isNotes = i == columns.count - 1
            let font: UIFont = (i >= 3 && i <= 6) ? .monospacedDigitSystemFont(ofSize: 8.5, weight: .regular) : .systemFont(ofSize: 8.5)
            let rect = isNotes
                ? CGRect(x: x + 4, y: y + 3, width: col.width - 8, height: rowHeight - 5)
                : CGRect(x: x + 4, y: y + 8, width: col.width - 8, height: 12)
            draw(values[i], in: rect, font: isNotes ? .systemFont(ofSize: 7.5) : font,
                 color: i == 0 ? muted : ink, alignment: col.alignment, lines: isNotes ? 2 : 1)
            x += col.width
        }
    }

    private static func drawTotalsRow(stats: LogStats, unit: DistanceUnit, y: CGFloat) -> CGFloat {
        let width = pageRect.width - 2 * margin
        ink.setFill()
        UIRectFill(CGRect(x: margin, y: y, width: width, height: 1))
        let font = UIFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold)
        var x = margin
        let values: [String] = ["", "TOTAL", "", Fmt.hours(minutes: stats.totalMinutes), Fmt.hours(minutes: stats.nightMinutes),
                                "", String(format: "%.1f", unit.value(fromMeters: stats.distanceMeters)), "", "Day \(Fmt.hours(minutes: stats.dayMinutes)) h"]
        for (i, col) in columns.enumerated() {
            draw(values[i], in: CGRect(x: x + 4, y: y + 8, width: col.width - 8, height: 12), font: font, color: ink, alignment: col.alignment)
            x += col.width
        }
        return y + rowHeight
    }

    private static func drawSignatureBlock(top: CGFloat) {
        let width = pageRect.width - 2 * margin
        draw("I certify that the driver named above completed the supervised driving recorded in this log.",
             in: CGRect(x: margin, y: top, width: width, height: 28), font: .systemFont(ofSize: 9.5), color: ink, alignment: .left, lines: 2)
        let lineY = top + 80
        let fields: [(String, CGFloat)] = [("Supervising adult signature", width * 0.42), ("Printed name", width * 0.33), ("Date", width * 0.25)]
        var x = margin
        for field in fields {
            ink.setFill()
            UIRectFill(CGRect(x: x, y: lineY, width: field.1 - 16, height: 0.8))
            draw(field.0, at: CGPoint(x: x, y: lineY + 5), font: .systemFont(ofSize: 8), color: muted)
            x += field.1
        }
        let lineY2 = lineY + 46
        x = margin
        for field in [("Driver signature", width * 0.42), ("Parent/guardian signature", width * 0.58)] {
            ink.setFill()
            UIRectFill(CGRect(x: x, y: lineY2, width: field.1 - 16, height: 0.8))
            draw(field.0, at: CGPoint(x: x, y: lineY2 + 5), font: .systemFont(ofSize: 8), color: muted)
            x += field.1
        }
    }

    private static func drawFooter(page: Int, of total: Int) {
        let y = pageRect.height - margin - 10
        draw("TrackMyDrive · Supervised Driving Log", at: CGPoint(x: margin, y: y), font: .systemFont(ofSize: 8), color: muted)
        draw("Page \(page) of \(total)", in: CGRect(x: pageRect.width - margin - 120, y: y, width: 120, height: 12),
             font: .systemFont(ofSize: 8), color: muted, alignment: .right)
    }

    // MARK: Text helpers

    private static func draw(_ text: String, at point: CGPoint, font: UIFont, color: UIColor) {
        (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }

    private static func draw(_ text: String, in rect: CGRect, font: UIFont, color: UIColor,
                             alignment: NSTextAlignment, lines: Int = 1) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        if lines == 1 {
            (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs, context: nil)
        } else {
            let limited = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: min(rect.height, font.lineHeight * CGFloat(lines) + 1))
            (text as NSString).draw(with: limited, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs, context: nil)
        }
    }
}
