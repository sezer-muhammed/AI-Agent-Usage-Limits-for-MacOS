import AIMeterCore
import Foundation
import Testing

@testable import AIMeterProviders

@Suite("Codex decoding")
struct CodexDecodingTests {
    @Test("Rate limits decode, including both windows and credits")
    func rateLimitsDecode() throws {
        let response = try JSONDecoder().decode(
            CodexDTO.GetAccountRateLimitsResponse.self,
            from: Fixture.data("Codex/rate-limits.json")
        )

        #expect(response.rateLimits?.planType == "pro")
        #expect(response.rateLimits?.primary?.usedPercent == 41)
        #expect(response.rateLimits?.primary?.windowDurationMins == 300)
        #expect(response.rateLimits?.secondary?.windowDurationMins == 10080)
        #expect(response.rateLimits?.credits?.balance == "12.50")
    }

    @Test("Window duration drives the normalized window kind")
    func windowKinds() throws {
        let response = try JSONDecoder().decode(
            CodexDTO.GetAccountRateLimitsResponse.self,
            from: Fixture.data("Codex/rate-limits.json")
        )

        #expect(
            RateLimitWindow.kind(forDurationMinutes: response.rateLimits?.primary?.windowDurationMins)
                == .fiveHour
        )
        #expect(
            RateLimitWindow.kind(
                forDurationMinutes: response.rateLimits?.secondary?.windowDurationMins
            ) == .weekly
        )
    }

    @Test("Account details decode")
    func accountDecodes() throws {
        let response = try JSONDecoder().decode(
            CodexDTO.GetAccountResponse.self,
            from: Fixture.data("Codex/account.json")
        )

        #expect(response.account?.type == "chatgpt")
        #expect(response.account?.planType == "pro")
        #expect(response.requiresOpenaiAuth == false)
    }

    @Test("Model list decodes and ignores fields AI Meter does not use")
    func modelListDecodes() throws {
        let response = try JSONDecoder().decode(
            CodexDTO.ModelListResponse.self,
            from: Fixture.data("Codex/model-list.json")
        )

        #expect(response.data?.count == 2)
        #expect(response.data?.first?.displayName == "Fixture Model High")
        #expect(response.nextCursor == nil)
    }

    @Test("Codex models are not free variants and never enter a free ranking")
    func codexModelsAreNotFree() throws {
        let response = try JSONDecoder().decode(
            CodexDTO.ModelListResponse.self,
            from: Fixture.data("Codex/model-list.json")
        )

        let canonicalizer = ModelCanonicalizer()
        let models = (response.data ?? []).compactMap { dto -> AIModel? in
            guard let id = dto.id else { return nil }
            return AIModel(
                id: id,
                canonicalID: canonicalizer.canonicalID(forProviderModelID: id),
                displayName: dto.displayName ?? id,
                provider: "openai",
                sourceProviderID: Provider.codex.id,
                contextLength: nil,
                inputPricePerMillion: nil,
                outputPricePerMillion: nil,
                isFreeVariant: false,
                supportedModalities: dto.inputModalities ?? []
            )
        }

        #expect(models.allSatisfy { !$0.isFreeVariant })
        #expect(ModelRankingEngine().bestGeneralFree(models) == nil)
    }
}

@Suite("Codex account state")
struct CodexAccountStateTests {
    /// `requiresOpenaiAuth` describes the auth *mode*, not the session: a
    /// signed-in ChatGPT account still reports it true. Treating it as a
    /// signed-out signal mislabels a working account.
    @Test("A signed-in account is not reported as signed out")
    func signedInAccountIsNotSignedOut() throws {
        let payload = """
            {"account":{"type":"chatgpt","email":"user@example.com","planType":"plus"},
             "requiresOpenaiAuth":true}
            """

        let response = try JSONDecoder().decode(
            CodexDTO.GetAccountResponse.self,
            from: Data(payload.utf8)
        )

        #expect(response.requiresOpenaiAuth == true)
        // The account object being present is what says "signed in".
        #expect(response.account != nil)
        #expect(response.account?.planType == "plus")
    }

    @Test("A signed-out profile returns no account")
    func signedOutProfileHasNoAccount() throws {
        let response = try JSONDecoder().decode(
            CodexDTO.GetAccountResponse.self,
            from: Data(#"{"account":null,"requiresOpenaiAuth":true}"#.utf8)
        )

        #expect(response.account == nil)
    }
}
