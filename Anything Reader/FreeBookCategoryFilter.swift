//
//  FreeBookCategoryFilter.swift
//  Anything Reader
//
//  Curated catalog categories used to filter the free books database.
//

import Foundation

struct FreeBookCategoryOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let aliases: [String]
    let section: String

    init(id: String, displayName: String, aliases: [String], section: String) {
        self.id = id
        self.displayName = displayName
        self.aliases = aliases
        self.section = section
    }
}

enum FreeBookCategoryFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case adventure
    case americanLiterature
    case britishLiterature
    case frenchLiterature
    case germanLiterature
    case russianLiterature
    case classicsOfLiterature
    case biographies
    case novels
    case shortStories
    case poetry
    case playsFilmsDramas
    case romance
    case scienceFictionFantasy
    case crimeThrillersMystery
    case mythologyLegendsFolklore
    case humour
    case childrenYoungAdultReading
    case literatureOther
    case engineeringTechnology
    case mathematics
    case sciencePhysics
    case scienceChemistryBiochemistry
    case scienceBiology
    case scienceEarthAgriculturalFarming
    case researchMethodsStatisticsInformationSys
    case environmentalIssues
    case historyAmerican
    case historyBritish
    case historyEuropean
    case historyAncient
    case historyMedievalMiddleAges
    case historyEarlyModern
    case historyModern
    case historyReligious
    case historyRoyalty
    case historyWarfare
    case historySchoolsUniversities
    case historyOther
    case archaeologyAnthropology
    case businessManagement
    case economics
    case lawCriminology
    case genderSexualityStudies
    case psychiatryPsychology
    case sociology
    case politics
    case parenthoodFamilyRelations
    case oldAgeAndElderly
    case art
    case architecture
    case music
    case fashion
    case journalismMediaWriting
    case languageCommunication
    case essaysLettersSpeeches
    case religionSpirituality
    case philosophyEthics
    case cookingDrinking
    case sportsHobbies
    case howTo
    case travelWriting
    case natureGardeningAnimals
    case sexualityErotica
    case healthMedicine
    case drugsAlcoholPharmacology
    case nutrition
    case encyclopediasDictionariesReference
    case teachingEducation
    case reportsConferenceProceedings
    case journals

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: return "All Categories"
        case .adventure: return "Adventure"
        case .americanLiterature: return "American Literature"
        case .britishLiterature: return "British Literature"
        case .frenchLiterature: return "French Literature"
        case .germanLiterature: return "German Literature"
        case .russianLiterature: return "Russian Literature"
        case .classicsOfLiterature: return "Classics of Literature"
        case .biographies: return "Biographies"
        case .novels: return "Novels"
        case .shortStories: return "Short Stories"
        case .poetry: return "Poetry"
        case .playsFilmsDramas: return "Plays/Films/Dramas"
        case .romance: return "Romance"
        case .scienceFictionFantasy: return "Science-Fiction & Fantasy"
        case .crimeThrillersMystery: return "Crime, Thrillers & Mystery"
        case .mythologyLegendsFolklore: return "Mythology, Legends & Folklore"
        case .humour: return "Humour"
        case .childrenYoungAdultReading: return "Children & Young Adult Reading"
        case .literatureOther: return "Literature - Other"
        case .engineeringTechnology: return "Engineering & Technology"
        case .mathematics: return "Mathematics"
        case .sciencePhysics: return "Science - Physics"
        case .scienceChemistryBiochemistry: return "Science - Chemistry/Biochemistry"
        case .scienceBiology: return "Science - Biology"
        case .scienceEarthAgriculturalFarming: return "Science - Earth/Agricultural/Farming"
        case .researchMethodsStatisticsInformationSys: return "Research Methods/Statistics/Information Sys"
        case .environmentalIssues: return "Environmental Issues"
        case .historyAmerican: return "History - American"
        case .historyBritish: return "History - British"
        case .historyEuropean: return "History - European"
        case .historyAncient: return "History - Ancient"
        case .historyMedievalMiddleAges: return "History - Medieval/Middle Ages"
        case .historyEarlyModern: return "History - Early Modern (c. 1450-1750)"
        case .historyModern: return "History - Modern (1750+)"
        case .historyReligious: return "History - Religious"
        case .historyRoyalty: return "History - Royalty"
        case .historyWarfare: return "History - Warfare"
        case .historySchoolsUniversities: return "History - Schools & Universities"
        case .historyOther: return "History - Other"
        case .archaeologyAnthropology: return "Archaeology & Anthropology"
        case .businessManagement: return "Business/Management"
        case .economics: return "Economics"
        case .lawCriminology: return "Law & Criminology"
        case .genderSexualityStudies: return "Gender & Sexuality Studies"
        case .psychiatryPsychology: return "Psychiatry/Psychology"
        case .sociology: return "Sociology"
        case .politics: return "Politics"
        case .parenthoodFamilyRelations: return "Parenthood & Family Relations"
        case .oldAgeAndElderly: return "Old Age & the Elderly"
        case .art: return "Art"
        case .architecture: return "Architecture"
        case .music: return "Music"
        case .fashion: return "Fashion"
        case .journalismMediaWriting: return "Journalism/Media/Writing"
        case .languageCommunication: return "Language & Communication"
        case .essaysLettersSpeeches: return "Essays, Letters & Speeches"
        case .religionSpirituality: return "Religion/Spirituality"
        case .philosophyEthics: return "Philosophy & Ethics"
        case .cookingDrinking: return "Cooking & Drinking"
        case .sportsHobbies: return "Sports/Hobbies"
        case .howTo: return "How To ..."
        case .travelWriting: return "Travel Writing"
        case .natureGardeningAnimals: return "Nature/Gardening/Animals"
        case .sexualityErotica: return "Sexuality & Erotica"
        case .healthMedicine: return "Health & Medicine"
        case .drugsAlcoholPharmacology: return "Drugs/Alcohol/Pharmacology"
        case .nutrition: return "Nutrition"
        case .encyclopediasDictionariesReference: return "Encyclopedias/Dictionaries/Reference"
        case .teachingEducation: return "Teaching & Education"
        case .reportsConferenceProceedings: return "Reports & Conference Proceedings"
        case .journals: return "Journals"
        }
    }

    var section: String {
        switch self {
        case .all: return "All"
        case .adventure, .americanLiterature, .britishLiterature, .frenchLiterature, .germanLiterature, .russianLiterature, .classicsOfLiterature, .biographies, .novels, .shortStories, .poetry, .playsFilmsDramas, .romance, .scienceFictionFantasy, .crimeThrillersMystery, .mythologyLegendsFolklore, .humour, .childrenYoungAdultReading, .literatureOther:
            return "Literature"
        case .engineeringTechnology, .mathematics, .sciencePhysics, .scienceChemistryBiochemistry, .scienceBiology, .scienceEarthAgriculturalFarming, .researchMethodsStatisticsInformationSys, .environmentalIssues:
            return "Science & Tech"
        case .historyAmerican, .historyBritish, .historyEuropean, .historyAncient, .historyMedievalMiddleAges, .historyEarlyModern, .historyModern, .historyReligious, .historyRoyalty, .historyWarfare, .historySchoolsUniversities, .historyOther:
            return "History"
        case .archaeologyAnthropology, .businessManagement, .economics, .lawCriminology, .genderSexualityStudies, .psychiatryPsychology, .sociology, .politics, .parenthoodFamilyRelations, .oldAgeAndElderly:
            return "Social Sciences"
        case .art, .architecture, .music, .fashion, .journalismMediaWriting, .languageCommunication, .essaysLettersSpeeches, .religionSpirituality, .philosophyEthics, .cookingDrinking, .sportsHobbies, .howTo, .travelWriting, .natureGardeningAnimals, .sexualityErotica, .healthMedicine, .drugsAlcoholPharmacology, .nutrition, .encyclopediasDictionariesReference, .teachingEducation, .reportsConferenceProceedings, .journals:
            return "Arts & Reference"
        }
    }

    static let menuSections: [String] = [
        "Literature",
        "Science & Tech",
        "History",
        "Social Sciences",
        "Arts & Reference"
    ]

    static func filters(in section: String) -> [FreeBookCategoryFilter] {
        allCases.filter { $0.section == section && !$0.isAll }
    }

    var aliases: [String] {
        switch self {
        case .all:
            return []
        case .adventure:
            return ["adventure", "category: adventure"]
        case .americanLiterature:
            return ["american literature", "category: american literature"]
        case .britishLiterature:
            return ["british literature", "category: british literature"]
        case .frenchLiterature:
            return ["french literature", "category: french literature"]
        case .germanLiterature:
            return ["german literature", "category: german literature"]
        case .russianLiterature:
            return ["russian literature", "category: russian literature"]
        case .classicsOfLiterature:
            return ["classics of literature", "classics", "best books ever listings", "category: classics of literature"]
        case .biographies:
            return ["biographies", "biography", "biographical"]
        case .novels:
            return ["novels", "novel", "category: novels"]
        case .shortStories:
            return ["short stories", "short story"]
        case .poetry:
            return ["poetry", "poems", "poem"]
        case .playsFilmsDramas:
            return ["plays", "films", "dramas", "drama", "play", "film", "category: plays"]
        case .romance:
            return ["romance", "romantic"]
        case .scienceFictionFantasy:
            return ["science fiction", "science-fiction", "science fiction and fantasy", "fantasy", "sci-fi"]
        case .crimeThrillersMystery:
            return ["crime", "thriller", "thrillers", "mystery", "mysteries", "detective"]
        case .mythologyLegendsFolklore:
            return ["mythology", "legends", "folklore", "myths"]
        case .humour:
            return ["humour", "humor", "comic", "comedy"]
        case .childrenYoungAdultReading:
            return ["children", "young adult", "ya reading", "juvenile"]
        case .literatureOther:
            return ["literature - other", "literature other", "literature"]
        case .engineeringTechnology:
            return ["engineering", "technology", "technical"]
        case .mathematics:
            return ["mathematics", "math"]
        case .sciencePhysics:
            return ["physics", "science - physics", "science: physics"]
        case .scienceChemistryBiochemistry:
            return ["chemistry", "biochemistry", "science - chemistry", "science: chemistry"]
        case .scienceBiology:
            return ["biology", "life sciences", "science - biology"]
        case .scienceEarthAgriculturalFarming:
            return ["earth science", "agricultural", "farming", "agriculture", "earth sciences"]
        case .researchMethodsStatisticsInformationSys:
            return ["research methods", "statistics", "information systems", "information sys"]
        case .environmentalIssues:
            return ["environmental", "climate", "ecology", "environment"]
        case .historyAmerican:
            return ["american history", "history: american"]
        case .historyBritish:
            return ["british history", "history: british"]
        case .historyEuropean:
            return ["european history", "history: european"]
        case .historyAncient:
            return ["ancient history", "history: ancient"]
        case .historyMedievalMiddleAges:
            return ["medieval", "middle ages", "history: medieval"]
        case .historyEarlyModern:
            return ["early modern", "history: early modern"]
        case .historyModern:
            return ["modern history", "history: modern"]
        case .historyReligious:
            return ["religious history", "history: religious"]
        case .historyRoyalty:
            return ["royalty", "royal", "history: royalty"]
        case .historyWarfare:
            return ["warfare", "military history", "wars", "history: warfare"]
        case .historySchoolsUniversities:
            return ["schools", "universities", "education history", "history: schools"]
        case .historyOther:
            return ["history - other", "history other"]
        case .archaeologyAnthropology:
            return ["archaeology", "anthropology", "archaeology & anthropology"]
        case .businessManagement:
            return ["business", "management", "business/management"]
        case .economics:
            return ["economics"]
        case .lawCriminology:
            return ["law", "criminology", "crime law", "law & criminology"]
        case .genderSexualityStudies:
            return ["gender", "sexuality studies", "gender & sexuality"]
        case .psychiatryPsychology:
            return ["psychiatry", "psychology", "psychiatry/psychology"]
        case .sociology:
            return ["sociology"]
        case .politics:
            return ["politics", "political science", "government"]
        case .parenthoodFamilyRelations:
            return ["parenthood", "family relations", "family"]
        case .oldAgeAndElderly:
            return ["old age", "elderly", "aging", "ageing"]
        case .art:
            return ["art", "arts"]
        case .architecture:
            return ["architecture"]
        case .music:
            return ["music"]
        case .fashion:
            return ["fashion"]
        case .journalismMediaWriting:
            return ["journalism", "media", "writing", "journalism/media/writing"]
        case .languageCommunication:
            return ["language", "communication", "linguistics", "language & communication"]
        case .essaysLettersSpeeches:
            return ["essays", "letters", "speeches", "essays, letters & speeches"]
        case .religionSpirituality:
            return ["religion", "spirituality", "religion/spirituality"]
        case .philosophyEthics:
            return ["philosophy", "ethics", "philosophy & ethics"]
        case .cookingDrinking:
            return ["cooking", "drinking", "food", "cooking & drinking"]
        case .sportsHobbies:
            return ["sports", "hobbies", "games", "sports/hobbies"]
        case .howTo:
            return ["how to", "how to ..."]
        case .travelWriting:
            return ["travel writing", "travel", "travel writing"]
        case .natureGardeningAnimals:
            return ["nature", "gardening", "animals", "nature/gardening/animals"]
        case .sexualityErotica:
            return ["sexuality", "erotica", "sexuality & erotica"]
        case .healthMedicine:
            return ["health", "medicine", "health & medicine"]
        case .drugsAlcoholPharmacology:
            return ["drugs", "alcohol", "pharmacology", "drugs/alcohol/pharmacology"]
        case .nutrition:
            return ["nutrition"]
        case .encyclopediasDictionariesReference:
            return ["encyclopedias", "dictionaries", "reference", "encyclopedias/dictionaries/reference"]
        case .teachingEducation:
            return ["teaching", "education", "teaching & education"]
        case .reportsConferenceProceedings:
            return ["reports", "conference proceedings", "reports & conference proceedings"]
        case .journals:
            return ["journals", "journal"]
        }
    }

    var isAll: Bool {
        self == .all
    }

    static var groupedDisplayOrder: [String: [FreeBookCategoryFilter]] {
        Dictionary(grouping: allCases, by: { $0.section })
    }

    static var mainCategories: [FreeBookCategoryFilter] {
        allCases.filter { !$0.isAll }
    }
}
