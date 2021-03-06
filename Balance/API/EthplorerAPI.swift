import Foundation
import CoreData

struct EthplorerAPI {
    private static let baseURL = URL(string: "https://api.ethplorer.io/")!
    private static let apiKey: String = {
        // Try to read from a plist file
        // Updates to this file are not checked into git, so for release, make sure you have the real key in your local file
        if let path = Bundle.main.path(forResource: "apikeys", ofType: "plist") {
            if let dictionary = NSDictionary(contentsOfFile: path), let apiKey = dictionary.value(forKey: "ethplorer") as? String {
                return apiKey
            }
        }
        
        // Default free api key
        return "freekey"
    }()
    
    public static let isFreeApiKey: Bool = {
        return apiKey == "freekey"
    }()
    
    static func loadWalletBalances(_ ethereumWallets: [EthereumWallet], completion: @escaping ([EthereumWallet]) -> ()) {
        DispatchQueue.utility.async {
            var returnWallets = [EthereumWallet]()
            let dispatchGroup = DispatchGroup()
            for ethereumWallet in ethereumWallets {
                dispatchGroup.enter()
                loadWalletBalance(ethereumWallet) { wallet, success in
                    returnWallets.append(wallet)
                    dispatchGroup.leave()
                }
                
                // If we're using the free api key, serialize the api calls with a delay in between
                if isFreeApiKey {
                    dispatchGroup.wait()
                    Thread.sleep(forTimeInterval: 2.0)
                }
            }
            dispatchGroup.wait()
            
            // Sort the new array to match the original array
            var sortedReturnWallets = [EthereumWallet]()
            for ethereumWallet in ethereumWallets {
                if let returnWallet = returnWallets.first(where: { $0.address == ethereumWallet.address }) {
                    sortedReturnWallets.append(returnWallet)
                }
            }
            
            DispatchQueue.main.async {
                completion(sortedReturnWallets)
            }
        }
    }
    
    static func loadWalletBalance(_ ethereumWallet: EthereumWallet, completion: @escaping (EthereumWallet, Bool) -> ()) {
        DispatchQueue.utility.async {
            var addressInfoResponse: AddressInfoResponse?
            let urlPath = baseURL.appendingPathComponent("getAddressInfo").appendingPathComponent(ethereumWallet.address)
            var urlComponents = URLComponents(url: urlPath, resolvingAgainstBaseURL: false)
            urlComponents?.queryItems = [URLQueryItem(name: "apiKey", value: apiKey)]
            guard let url = urlComponents?.url else {
                DispatchQueue.main.async {
                    completion(ethereumWallet, false)
                }
                return
            }
            
            let task = URLSession.shared.dataTask(with: url) { data, response, error in
                guard let data = data, error == nil else {
                    print(error?.localizedDescription ?? "Response Error")
                    return
                }
                
                do {
                    addressInfoResponse = try JSONDecoder().decode(AddressInfoResponse.self, from: data)
                } catch {
                    print("Error getting address info for \(ethereumWallet.address): ", error)
                }
                
                // Convert to Balance model
                var returnWallet = ethereumWallet
                if let addressInfoResponse = addressInfoResponse, let ETH = addressInfoResponse.ETH {
                    returnWallet.balance = ETH.balance
                    if let tokensResponse = addressInfoResponse.tokens {
                        var tokens = [Token]()
                        for tokenInfoWrapper in tokensResponse {
                            let info = tokenInfoWrapper.tokenInfo
                            var decimalsInt: UInt?
                            if let decimalsString = info?.decimals {
                                decimalsInt = UInt(decimalsString)
                            }
                            
                            var cryptoBalance: Double?
                            if let balance = tokenInfoWrapper.balance, let decimalsInt = decimalsInt {
                                cryptoBalance = balance / pow(10.0, Double(decimalsInt))
                            }
                            
                            var fiatBalance: Double?
                            if let cryptoBalance = cryptoBalance, let rate = info?.price?.rate {
                                fiatBalance = cryptoBalance * rate
                            }
                            
                            let token = Token(balance: cryptoBalance, fiatBalance: fiatBalance, rate: info?.price?.rate, currency: info?.price?.currency, address: info?.address, name: info?.name, symbol: info?.symbol, decimals: decimalsInt)
                            tokens.append(token)
                        }
                        returnWallet.tokens = tokens
                    }
                }
                
                DispatchQueue.main.async {
                    completion(returnWallet, true)
                }
            }
            task.resume()
        }
    }
    
    static func loadGetAddressInfo(_ ethereumWallets: [NSManagedObject], completion: @escaping ([AddressInfoResponse]) -> ()) {
        DispatchQueue.utility.async {
            let addresses = ethereumWallets.compactMap { maker in
                maker.value(forKey: "address") as? String
            }
            
            var addressInfoResponses = [AddressInfoResponse]()
            let dispatchGroup = DispatchGroup()
            for address in addresses {
                dispatchGroup.enter()
                loadGetAddressInfo(address: address) { response in
                    if let response = response {
                        addressInfoResponses.append(response)
                    }
                    dispatchGroup.leave()
                }
            }
            dispatchGroup.wait()
            
            DispatchQueue.main.async {
                completion(addressInfoResponses)
            }
        }
    }
    
    static func loadGetAddressInfo(address: String, completion: @escaping (AddressInfoResponse?) -> ()) {
        DispatchQueue.utility.async {
            var addressInfoResponse: AddressInfoResponse?
            let urlPath = baseURL.appendingPathComponent("getAddressInfo").appendingPathComponent(address)
            var urlComponents = URLComponents(url: urlPath, resolvingAgainstBaseURL: false)
            urlComponents?.queryItems = [URLQueryItem(name: "apiKey", value: apiKey)]
            guard let url = urlComponents?.url else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            let task = URLSession.shared.dataTask(with: url) { data, response, error in
                guard let data = data, error == nil else {
                    print(error?.localizedDescription ?? "Response Error")
                    return
                }
                
                do {
                    addressInfoResponse = try JSONDecoder().decode(AddressInfoResponse.self, from: data)
                } catch {
                    print("Error getting address info for \(address): ", error)
                }
                
                DispatchQueue.main.async {
                    completion(addressInfoResponse)
                }
            }
            task.resume()
        }
    }
    
    struct AddressInfoResponse: Decodable {
        let address: String?
        let ETH: ETHResponse?
        let countTxs: UInt64?
        let tokens: [TokenInfoWrapperResponse]?
    }
    
    struct ETHResponse: Codable {
        let balance: Double?
        
        private enum CodingKeys: String, CodingKey {
            case balance = "balance"
        }
    }
    
    struct TokenInfoWrapperResponse: Codable {
        let tokenInfo: TokenInfoResponse?
        let balance: Double?
        
        private enum CodingKeys: String, CodingKey {
            case tokenInfo = "tokenInfo"
            case balance   = "balance"
        }
    }
    
    struct TokenInfoResponse: Codable {
        let address: String?
        let name: String?
        let decimals: String?
        let symbol: String?
        let totalSupply: String?
        let owner: String?
        let lastUpdated: UInt64?
        let issuancesCount: UInt64?
        let holdersCount: UInt64?
        let ethTransfersCount: UInt64?
        let price: PriceResponse?
        
        private enum CodingKeys: String, CodingKey {
            case address           = "address"
            case name              = "name"
            case decimals          = "decimals"
            case symbol            = "symbol"
            case totalSupply       = "totalSupply"
            case owner             = "owner"
            case lastUpdated       = "lastUpdated"
            case issuancesCount    = "issuancesCount"
            case holdersCount      = "holdersCount"
            case ethTransfersCount = "ethTransfersCount"
            case price             = "price"
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            address = try? container.decode(String.self, forKey: .address)
            name = try? container.decode(String.self, forKey: .name)
            decimals = try? container.decode(String.self, forKey: .decimals)
            symbol = try? container.decode(String.self, forKey: .symbol)
            totalSupply = try? container.decode(String.self, forKey: .totalSupply)
            owner = try? container.decode(String.self, forKey: .owner)
            lastUpdated = try? container.decode(UInt64.self, forKey: .lastUpdated)
            issuancesCount = try? container.decode(UInt64.self, forKey: .issuancesCount)
            holdersCount = try? container.decode(UInt64.self, forKey: .holdersCount)
            ethTransfersCount = try? container.decode(UInt64.self, forKey: .ethTransfersCount)
            
            // Handle possible boolean value in price field
            do {
                _ = try container.decode(Bool.self, forKey: .price)
                price = nil
            } catch {
                price = try? container.decode(PriceResponse.self, forKey: .price)
            }
        }
    }
    
    struct PriceResponse: Codable {
        let rate: Double?
        let diff: Double?
        let diff7d: Double?
        let ts: UInt64?
        let marketCapUsd: Double?
        let availableSupply: Double?
        let volume24h: Double?
        let diff30d: Double?
        let currency: String?
        
        private enum CodingKeys: String, CodingKey {
            case rate            = "rate"
            case diff            = "diff"
            case diff7d          = "diff7d"
            case ts              = "ts"
            case marketCapUsd    = "marketCapUsd"
            case availableSupply = "availableSupply"
            case volume24h       = "volume24h"
            case diff30d         = "diff30d"
            case currency        = "currency"
        }
    }
}
