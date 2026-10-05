import Foundation
import SwiftUI

// MARK: - Models (parity with Android OnboardingModels.kt)

enum PageTemplate: String, CaseIterable, Identifiable {
    case consulting, sales, blank
    var id: String { rawValue }
    var title: String {
        switch self {
        case .consulting: return "Consulting"
        case .sales: return "Sales"
        case .blank: return "Blank"
        }
    }
    var blurb: String {
        switch self {
        case .consulting: return "Book calls and consultations — clients pick a time, your AI agent handles the rest."
        case .sales: return "Sell products with a catalog, buy buttons and checkout built in."
        case .blank: return "Start from an empty page and build it your way."
        }
    }
    var icon: String {
        switch self {
        case .consulting: return "calendar.badge.clock"
        case .sales: return "bag"
        case .blank: return "doc"
        }
    }
}

enum OnboardingStep {
    case checking, details, template, creating, createError
    case researchOffer, researching, researchDone, done
}

struct SessionExpiredError: Error {}

// MARK: - ViewModel (parity with Android OnboardingViewModel)

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var step: OnboardingStep = .checking
    @Published var businessName = ""
    @Published var website = ""
    @Published var nameError: String?
    @Published var websiteError: String?
    @Published var loadError: String?
    @Published var template: PageTemplate?
    @Published var createError: String?
    @Published var createdPageId: String?
    @Published var createdPageTitle: String?
    @Published var researchElapsedSeconds = 0
    @Published var researchProductsFound: Int?
    @Published var researchError: String?
    @Published var sessionExpired = false

    private var researchTimer: Timer?

    /// Zero-pages gate: CHECKING → DETAILS (no pages) or signal done (has pages).
    func checkPages() async -> Bool {
        step = .checking
        do {
            let pages = try await CallPagesAPI.shared.pages()
            if pages.isEmpty {
                step = .details
                return false
            }
            return true
        } catch APIError.unauthorized {
            sessionExpired = true
            return false
        } catch {
            loadError = "Couldn't load your pages. Check your connection and retry."
            return false
        }
    }

    func submitDetails() {
        nameError = nil
        websiteError = nil
        let name = businessName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            nameError = "Please enter your business name."
            return
        }
        let site = website.trimmingCharacters(in: .whitespaces)
        if !site.isEmpty, !isValidURL(site) {
            websiteError = "That doesn't look like a valid website URL."
            return
        }
        step = .template
    }

    func createPage() async {
        guard let template else { return }
        step = .creating
        createError = nil
        do {
            let page = try await CallPagesAPI.shared.createPage(
                title: businessName.trimmingCharacters(in: .whitespaces),
                businessName: businessName.trimmingCharacters(in: .whitespaces),
                template: template.rawValue,
                website: website.trimmingCharacters(in: .whitespaces).isEmpty
                    ? nil
                    : website.trimmingCharacters(in: .whitespaces)
            )
            createdPageId = page.id
            createdPageTitle = page.displayName
            if website.trimmingCharacters(in: .whitespaces).isEmpty {
                step = .done
            } else {
                step = .researchOffer
            }
        } catch APIError.unauthorized {
            sessionExpired = true
        } catch {
            createError = "Couldn't create your page. Please try again."
            step = .createError
        }
    }

    func startResearch() async {
        guard let pageId = createdPageId else { return }
        step = .researching
        researchElapsedSeconds = 0
        researchError = nil
        researchTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.researchElapsedSeconds += 1 }
        }
        do {
            let result = try await CallPagesAPI.shared.researchPage(pageId: pageId)
            researchProductsFound = result.productsKept
            step = .researchDone
        } catch APIError.unauthorized {
            sessionExpired = true
        } catch {
            // Non-blocking: the user can always continue.
            researchError = "Import didn't finish, but your page is ready. You can import later from the dashboard."
            step = .researchDone
        }
        researchTimer?.invalidate()
    }

    func skipResearch() {
        step = .done
    }

    private func isValidURL(_ s: String) -> Bool {
        var str = s
        if !str.contains("://") { str = "https://" + str }
        guard let url = URL(string: str), let host = url.host, host.contains(".") else { return false }
        return true
    }
}
