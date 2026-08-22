import SwiftUI

/// Shown when `Config.xcconfig` still holds the template values, so a fresh clone
/// launches and explains itself instead of failing at the first network call.
struct SetupRequiredView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.accent)

            VStack(spacing: 10) {
                Text("Connect Supabase")
                    .font(.title2.weight(.semibold))
                Text("TravelMap needs a Supabase project before you can sign in.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                setupStep(number: 1, text: "Copy Config.xcconfig.example to Config.xcconfig")
                setupStep(number: 2, text: "Paste your project URL and anon key from Supabase → Settings → API")
                setupStep(number: 3, text: "Run supabase/schema.sql in the SQL editor, then rebuild")
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private func setupStep(number: Int, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.footnote.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(AppTheme.accent, in: .circle)
            Text(text)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    SetupRequiredView()
}
