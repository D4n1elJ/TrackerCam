# Associations

## Association Types

| Type | Meaning | FK Lives On | Example |
|---|---|---|---|
| `belongsTo` | "I point to another record" | This record's table | Book belongs to Author |
| `hasOne` | "Another record points to me (1:1)" | Other table | Author has one Profile |
| `hasMany` | "Many records point to me (1:N)" | Other table | Author has many Books |
| `hasMany(through:)` | Many-to-many via pivot | Pivot table | Country has many Citizens through Passports |
| `hasOne(through:)` | 1:1 through intermediate | Intermediate table | Book has one ReturnAddress through Library |

## Declaring Associations

```swift
extension Book {
    static let author = belongsTo(Author.self)
    var author: QueryInterfaceRequest<Author> {
        request(for: Book.author)
    }
}

extension Author {
    static let books = hasMany(Book.self)
    var books: QueryInterfaceRequest<Book> {
        request(for: Author.books)
    }
}
```

GRDB infers foreign keys from table names. The `books` table must have an `authorId` column referencing `author(id)`.

## Many-to-Many (HasManyThrough)

```swift
struct Passport: TableRecord {
    static let citizen = belongsTo(Citizen.self)
    static let country = belongsTo(Country.self)
}

struct Country: TableRecord {
    static let passports = hasMany(Passport.self)
    static let citizens = hasMany(Citizen.self, through: passports, using: Passport.citizen)
}

struct Citizen: TableRecord {
    static let passports = hasMany(Passport.self)
    static let countries = hasMany(Country.self, through: passports, using: Passport.country)
}
```

## Disambiguating Multiple Foreign Keys

When a table has multiple FKs to the same destination:

```swift
struct Book: TableRecord {
    static let authorForeignKey = ForeignKey(["authorId"])
    static let translatorForeignKey = ForeignKey(["translatorId"])

    static let author = belongsTo(Person.self, using: authorForeignKey)
    static let translator = belongsTo(Person.self, using: translatorForeignKey)
}

struct Person: TableRecord {
    static let writtenBooks = hasMany(Book.self, using: Book.authorForeignKey)
    static let translatedBooks = hasMany(Book.self, using: Book.translatorForeignKey)
}
```

## Eager Loading (Joining Methods)

| Method | SQL | Use For |
|---|---|---|
| `including(required:)` | JOIN | To-one, must exist (inner join) |
| `including(optional:)` | LEFT JOIN | To-one, may be nil |
| `including(all:)` | Separate query | To-many collections |
| `joining(required:)` | JOIN | Filtering only (no data fetched) |
| `joining(optional:)` | LEFT JOIN | Filtering only (no data fetched) |
| `annotated(withRequired:)` | JOIN + selected cols | Aggregate columns from to-one |
| `annotated(withOptional:)` | LEFT JOIN + selected cols | Aggregate columns from to-one |

### Fetching To-One

```swift
struct BookInfo: Decodable, FetchableRecord {
    var book: Book
    var author: Author?  // property name MUST match association key
}

let bookInfos = try Book
    .including(optional: Book.author)
    .asRequest(of: BookInfo.self)
    .fetchAll(db)
```

### Fetching To-Many

```swift
struct AuthorInfo: Decodable, FetchableRecord {
    var author: Author
    var books: [Book]  // property name MUST match association key (pluralised)
}

let authorInfos = try Author
    .including(all: Author.books)
    .asRequest(of: AuthorInfo.self)
    .fetchAll(db)
```

## Association Aggregates

Available on hasMany / hasManyThrough associations:

| Aggregate | Example |
|---|---|
| `.count` | `Author.books.count` |
| `.isEmpty` | `Author.books.isEmpty` |
| `.min(column)` | `Author.books.min(Column("year"))` |
| `.max(column)` | `Author.books.max(Column("year"))` |
| `.average(column)` | `Author.books.average(Column("price"))` |
| `.sum(column)` / `.total(column)` | `Author.books.sum(Column("sales"))` |

### Annotating with Aggregates

```swift
struct AuthorInfo: Decodable, FetchableRecord {
    var author: Author
    var bookCount: Int
    var maxBookYear: Int?
}

let request = Author.annotated(with:
    Author.books.count,
    Author.books.max(Column("year")))
```

Default naming: `bookCount`, `minBookYear`, `maxBookYear`, `averageBookPrice`, `bookSalesSum`. Override with `.forKey("customName")`.

### Filtering with Aggregates

```swift
// Authors with 20+ books
Author.having(Author.books.count >= 20)

// Authors with no books
Author.having(Author.books.isEmpty)

// Authors whose latest book is after 2020
Author.having(Author.books.max(Column("year")) > 2020)
```

## Composable Scopes via DerivableRequest

```swift
extension DerivableRequest<Author> {
    func fromCountry(_ code: String) -> Self {
        filter(Column("countryCode") == code)
    }
}

extension DerivableRequest<Book> {
    func byAuthorFrom(_ country: String) -> Self {
        joining(required: Book.author.fromCountry(country))
    }
}

// Chain them
Book.all().byAuthorFrom("FR").order(Column("title"))
```

## Pitfalls

### Association key must match Decodable property name

The property name in your Decodable struct must match the association key. By default:
- `belongsTo(Author.self)` → key is `"author"` (singular)
- `hasMany(Book.self)` → key is `"books"` (plural)

Mismatch causes silent nil values or decoding failures.

### Cannot chain required behind optional

```swift
// FATAL ERROR at runtime — not implemented
Book.joining(optional: Book.author.including(required: Person.country))
```

Workaround: use two separate joins or restructure the query.

### including(all:) limitations

- Cannot use table aliases to filter on parent columns
- Cannot be combined with `limit`, `distinct`, `group`, `having`, or association aggregates in the same request
- Attempting these with other joining methods causes a fatal error

### Multiple aggregates on the same population

Multiple aggregates on the same hasMany association work correctly. But if you aggregate the same column through different association paths, counts can get cross-multiplied. Use different association keys or raw SQL for complex multi-path aggregations.

### Self-referencing associations

Supported but require explicit foreign key specification:

```swift
struct Employee: TableRecord {
    static let managerFK = ForeignKey(["managerId"])
    static let manager = belongsTo(Employee.self, using: managerFK)
    static let reports = hasMany(Employee.self, using: managerFK)
}
```
