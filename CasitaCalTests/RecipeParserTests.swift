import CoreData
import Foundation
import Testing
@testable import CasitaCal

struct RecipeParserTests {
    let url = URL(string: "https://www.example.com/recipes/tacos")!

    @Test func readsYoastStyleGraphWithSections() throws {
        let html = """
        <html><head>
        <meta property="og:site_name" content="Taco Blog &amp; Co" />
        <script type="application/ld+json" class="yoast-schema-graph">
        {"@context":"https://schema.org","@graph":[
          {"@type":"WebPage","name":"ignore me"},
          {"@type":["Recipe"],"name":"Fish Tacos &#8211; Easy","image":["https://cdn.example.com/1x1.jpg","https://cdn.example.com/16x9.jpg"],
           "recipeIngredient":["1 lb cod","8 tortillas","<b>1</b> lime"],
           "recipeInstructions":[
             {"@type":"HowToSection","name":"Fish","itemListElement":[{"@type":"HowToStep","text":"Season the fish."},{"@type":"HowToStep","text":"Grill 4 minutes."}]},
             {"@type":"HowToSection","name":"Assemble","itemListElement":[{"@type":"HowToStep","text":"Fill tortillas."}]}
           ],
           "prepTime":"PT15M","cookTime":"PT10M","recipeYield":["4","4 servings"]}
        ]}
        </script></head><body></body></html>
        """
        let r = try #require(RecipeParser.parse(html: html, url: url))
        #expect(r.title == "Fish Tacos – Easy")
        #expect(r.siteName == "Taco Blog & Co")
        #expect(r.imageURL?.absoluteString == "https://cdn.example.com/1x1.jpg")
        #expect(r.ingredients == ["1 lb cod", "8 tortillas", "1 lime"])
        #expect(r.steps == ["## Fish", "Season the fish.", "Grill 4 minutes.", "## Assemble", "Fill tortillas."])
        #expect(r.prepMinutes == 15 && r.cookMinutes == 10 && r.totalMinutes == 25)
        #expect(r.servings == "4 servings")
        #expect(r.hasRecipeDetails)
    }

    @Test func readsPlainRecipeWithStringInstructionsAndImageObject() throws {
        let html = """
        <script type='application/ld+json'>
        [{"@type":"Recipe","name":"Pancakes","image":{"@type":"ImageObject","url":"/img/pancakes.jpg"},
          "recipeIngredient":"1 cup flour\\n1 egg","recipeInstructions":"<ol><li>Mix.</li><li>Cook.</li></ol>",
          "totalTime":"P0DT1H5M","recipeYield":6}]
        </script>
        """
        let r = try #require(RecipeParser.parse(html: html, url: url))
        #expect(r.imageURL?.absoluteString == "https://www.example.com/img/pancakes.jpg")
        #expect(r.ingredients == ["1 cup flour", "1 egg"])
        #expect(r.steps == ["Mix.", "Cook."])
        #expect(r.totalMinutes == 65)
        #expect(r.servings == "Serves 6")
    }

    @Test func toleratesRawNewlinesInJSON() throws {
        let html = "<script type=\"application/ld+json\">{\"@type\":\"Recipe\",\"name\":\"Soup\",\"recipeIngredient\":[\"water\"],\"description\":\"Line one\nline two\"}</script>"
        let r = try #require(RecipeParser.parse(html: html, url: url))
        #expect(r.title == "Soup")
        #expect(r.summary == "Line one line two")
    }

    @Test func fallsBackToLinkPreview() throws {
        let html = """
        <html><head><title>Ignored title</title>
        <meta content="Grandma's Lasagna" property="og:title">
        <meta property="og:image" content="https://cdn.example.com/lasagna.jpg">
        </head></html>
        """
        let r = try #require(RecipeParser.parse(html: html, url: url))
        #expect(r.title == "Grandma's Lasagna")
        #expect(r.imageURL?.absoluteString == "https://cdn.example.com/lasagna.jpg")
        #expect(r.siteName == "example.com")
        #expect(!r.hasRecipeDetails)
    }

    @Test func parsesDurations() {
        #expect(RecipeParser.minutes("PT1H30M") == 90)
        #expect(RecipeParser.minutes("PT90M") == 90)
        #expect(RecipeParser.minutes("P0DT0H45M") == 45)
        #expect(RecipeParser.minutes("PT0.5H") == 30)
        #expect(RecipeParser.minutes("P1D") == 1440)
        #expect(RecipeParser.minutes(nil) == 0)
        #expect(RecipeParser.minutes("20 minutes") == 0)
    }

    @Test func findsLinkInSharedText() {
        let u = RecipeImporter.firstLink(in: "Try this! https://www.allrecipes.com/recipe/16354/easy-meatloaf/ so good")
        #expect(u?.host() == "www.allrecipes.com")
        #expect(RecipeImporter.firstLink(in: "no link here") == nil)
    }

    @Test @MainActor func savingSameLinkTwiceKeepsOneRecipe() {
        let p = Persistence(inMemory: true)
        let parsed = ParsedRecipe(title: "Tacos", sourceURL: url)
        let a = RecipeImporter.save(parsed, image: nil, persistence: p)
        RecipeImporter.plan(a, day: "2026-11-09", slot: "dinner", persistence: p)
        var again = parsed
        again.title = "Better Tacos"
        let b = RecipeImporter.save(again, image: nil, persistence: p)
        p.save()
        #expect(a.objectID == b.objectID)
        #expect((try? p.context.count(for: .init(entityName: "CDRecipe"))) == 1)
        let meal = try? p.context.fetch(NSFetchRequest<CDMeal>(entityName: "CDMeal")).first
        #expect(meal?.recipe == a && meal?.title == "Tacos")
    }
}
