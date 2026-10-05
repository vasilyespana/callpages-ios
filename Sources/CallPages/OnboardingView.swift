import SwiftUI

/// Native first-run page-creation flow (parity with Android OnboardingScreen).
struct OnboardingView: View {
    @StateObject private var vm = OnboardingViewModel()
    var onFinished: () -> Void

    var body: some View {
        Group {
            switch vm.step {
            case .checking:
                ProgressView("Checking your pages…")
            case .details:
                detailsStep
            case .template:
                templateStep
            case .creating:
                ProgressView("Creating your page…")
            case .createError:
                VStack(spacing: 16) {
                    Text("Couldn't create your page").font(.headline)
                    if let e = vm.createError { Text(e).foregroundStyle(.secondary) }
                    Button("Try again") { Task { await vm.createPage() } }
                        .buttonStyle(.borderedProminent)
                }.padding()
            case .researchOffer:
                researchOfferStep
            case .researching:
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Importing your website… \(vm.researchElapsedSeconds)s")
                        .foregroundStyle(.secondary)
                    Text("This can take a minute. We're pulling your products and style.")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }.padding()
            case .researchDone:
                researchDoneStep
            case .done:
                doneStep
            }
        }
        .task {
            let hasPages = await vm.checkPages()
            if hasPages { onFinished() }
        }
        .onChange(of: vm.sessionExpired) { expired in
            if expired { AuthService.shared.isSignedIn = false }
        }
    }

    private var detailsStep: some View {
        Form {
            Section("Your business") {
                TextField("Business name", text: $vm.businessName)
                    .textInputAutocapitalization(.words)
                if let e = vm.nameError {
                    Text(e).foregroundStyle(.red).font(.caption)
                }
                TextField("Website (optional)", text: $vm.website)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                if let e = vm.websiteError {
                    Text(e).foregroundStyle(.red).font(.caption)
                }
            }
            Section {
                Button("Continue") { vm.submitDetails() }
                    .frame(maxWidth: .infinity)
            }
            if let e = vm.loadError {
                Section { Text(e).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Create your page")
    }

    private var templateStep: some View {
        List(PageTemplate.allCases) { t in
            Button {
                vm.template = t
                Task { await vm.createPage() }
            } label: {
                HStack {
                    Image(systemName: t.icon)
                        .font(.title2)
                        .frame(width: 44)
                    VStack(alignment: .leading) {
                        Text(t.title).font(.headline)
                        Text(t.blurb).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Pick a template")
    }

    private var researchOfferStep: some View {
        VStack(spacing: 20) {
            Text("🔍").font(.system(size: 60))
            Text("Import your website?").font(.title2.bold())
            Text("We can pull your products, prices, photos, and brand style from \(vm.website) automatically.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Yes, import it") { Task { await vm.startResearch() } }
                .buttonStyle(.borderedProminent)
            Button("Skip for now") { vm.skipResearch() }
        }
        .padding()
    }

    private var researchDoneStep: some View {
        VStack(spacing: 20) {
            if let err = vm.researchError {
                Text("⚠️").font(.system(size: 60))
                Text(err)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                Text("✅").font(.system(size: 60))
                Text("Imported \(vm.researchProductsFound ?? 0) products")
                    .font(.title2.bold())
                Text("Your page is ready to review in the dashboard.")
                    .foregroundStyle(.secondary)
            }
            Button("Open my page") { onFinished() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var doneStep: some View {
        VStack(spacing: 20) {
            Text("🎉").font(.system(size: 60))
            Text("Your page is ready!").font(.title2.bold())
            if let title = vm.createdPageTitle {
                Text(title).foregroundStyle(.secondary)
            }
            Button("Go to dashboard") { onFinished() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
