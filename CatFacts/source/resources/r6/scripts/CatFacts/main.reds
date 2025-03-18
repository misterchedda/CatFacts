import Codeware.*
import Codeware.UI.*
import RedData.Json.*
import RedHttpClient.*

// Delay callback for scheduling cat fact fetches
public class CatFactUpdateCallback extends DelayCallback {
  private let m_system: wref<CatFactSystem>;

  public func Call() {
    if IsDefined(this.m_system) {
      // // FTLog("CatFactUpdateCallback: Running FetchCatFact");
      this.m_system.FetchCatFact();
    } else {
      // // FTLog("CatFactUpdateCallback: Error - system not defined");
    }
  }

  public static func Create(system: ref<CatFactSystem>) -> ref<CatFactUpdateCallback> {
    let self = new CatFactUpdateCallback();
    self.m_system = system;
    return self;
  }
}

// Settings class for enabling the mod and setting fetch frequency
public class CatFactSettings extends ScriptableSystem {
  @runtimeProperty("ModSettings.mod", "CatFacts")
  @runtimeProperty("ModSettings.displayName", "Enable")
  @runtimeProperty("ModSettings.description", "Enable or disable the mod")
  let enabled: Bool = true;

  @runtimeProperty("ModSettings.mod", "CatFacts")
  @runtimeProperty("ModSettings.category", "General Settings")
  @runtimeProperty("ModSettings.category.order", "1")
  @runtimeProperty("ModSettings.displayName", "Frequency (minutes)")
  @runtimeProperty("ModSettings.description", "How often to fetch new cat facts (in minutes)")
  @runtimeProperty("ModSettings.step", "5")
  @runtimeProperty("ModSettings.min", "5")
  @runtimeProperty("ModSettings.max", "120")
  @runtimeProperty("ModSettings.dependency", "enabled")
  let frequency: Int32 = 1;

  @runtimeProperty("ModSettings.mod", "CatFacts")
  @runtimeProperty("ModSettings.category", "General Settings")
  @runtimeProperty("ModSettings.category.order", "2")
  @runtimeProperty("ModSettings.displayName", "Use Dog Facts")
  @runtimeProperty("ModSettings.description", "Fetch dog facts instead of cat facts")
  let useDogFacts: Bool = false;

  public static func Get(gi: GameInstance) -> ref<CatFactSettings> {
    return GameInstance.GetScriptableSystemsContainer(gi).Get(n"CatFactSettings") as CatFactSettings;
  }

  @if(ModuleExists("ModSettingsModule"))
  private func OnAttach() -> Void {
    ModSettings.RegisterListenerToClass(this);
    ModSettings.RegisterListenerToModifications(this);
  }

  @if(!ModuleExists("ModSettingsModule"))
  private func OnAttach() -> Void {
  }

  @if(ModuleExists("ModSettingsModule"))
  private func OnModSettingsChange() -> Void {
    if this.enabled {
      let gi = this.GetGameInstance();
      // FTLog("OnModSettingsChange: Resetting cat fact system");
      let catFactSystem = GameInstance.GetScriptableSystemsContainer(gi).Get(n"CatFactSystem") as CatFactSystem;
      if IsDefined(catFactSystem) {
        catFactSystem.ResetCycleAndFetchImmediately();
      }
    }
  }

  @if(ModuleExists("ModSettingsModule"))
  private func OnDetach() -> Void {
    ModSettings.UnregisterListenerToClass(this);
    ModSettings.UnregisterListenerToModifications(this);
  }

  @if(!ModuleExists("ModSettingsModule"))
  private func OnDetach() -> Void {
  }
}

// Delay callback for sending the intro message
public class CatFactIntroMessageCallback extends DelayCallback {
  private let m_system: wref<CatFactJournalManager>;

  public func Call() {
    if IsDefined(this.m_system) {
      this.m_system.SendIntroMessage();
    }
  }

  public static func Create(system: ref<CatFactJournalManager>) -> ref<CatFactIntroMessageCallback> {
    let self = new CatFactIntroMessageCallback();
    self.m_system = system;
    return self;
  }
}

// Service to count the number of cat fact messages sent
public class CatFactMessageCounterService extends ScriptableService {
  private persistent let m_messageCount: Int32;

  public func IncrementMessageCount() -> Void {
    this.m_messageCount += 1;
  }

  public func GetMessageCount() -> Int32 {
    return this.m_messageCount;
  }
}

// Main system class to handle cat fact fetching and scheduling
public class CatFactSystem extends ScriptableSystem {
  private let m_callbackSystem: wref<CallbackSystem>;
  private let m_delaySystem: wref<DelaySystem>;
  private let m_isFirstCheck: Bool;
  private let m_settings: ref<CatFactSettings>;
  private let m_catFacts: array<String>;
  private let m_messageCounterService: ref<CatFactMessageCounterService>;
  private let m_nextFetchDelayID: DelayID;

  private func OnAttach() {
    this.m_settings = CatFactSettings.Get(GetGameInstance());
    if this.m_settings.enabled {
      this.m_callbackSystem = GameInstance.GetCallbackSystem();
      this.m_delaySystem = GameInstance.GetDelaySystem(this.GetGameInstance());
      this.m_messageCounterService = GameInstance.GetScriptableServiceContainer().GetService(n"CatFactMessageCounterService") as CatFactMessageCounterService;
      this.m_callbackSystem.RegisterCallback(n"Session/Ready", this, n"OnSessionReady");
      this.m_isFirstCheck = true;
    }
  }

  private func OnDetach() {
    this.m_callbackSystem.UnregisterCallback(n"Session/Ready", this, n"OnSessionReady");
    this.m_callbackSystem = null;
    this.m_delaySystem = null;
  }

  private cb func OnSessionReady(event: ref<GameSessionEvent>) {
    if this.m_settings.enabled {
      let isPreGame = event.IsPreGame();
      if !isPreGame {
        // // FTLog("== Scheduling initial FetchCatFact ==");
        this.ScheduleNextCheck();
        
        // Check the fact to determine if the intro message should be sent
        let questsSystem = GameInstance.GetQuestsSystem(this.GetGameInstance());
        let factValue = questsSystem.GetFactStr("mchedda_catfacts_contact_added");
        // // FTLog(s"[CatFacts] Fact 'mchedda_catfacts_contact_added': \(factValue)");
        
        if factValue == 0 {
          let delaySystem = GameInstance.GetDelaySystem(GetGameInstance());
          delaySystem.DelayCallback(CatFactIntroMessageCallback.Create(CatFactJournalManager.GetCatFactJournalManager()), 4.0, false);
        }
      }
    }
  }


  private func ScheduleNextCheck() {
    let delay: Float;
    if this.m_isFirstCheck {
      delay = 20.0; // 20 seconds for the first fetch
      this.m_isFirstCheck = false;
    } else {
      delay = Cast<Float>(this.m_settings.frequency) * 60.0;
    }
    let isAffectedByTimeDilation: Bool = false;
    // // FTLog(s"== Scheduling next FetchCatFact in \(delay) seconds ==");
    this.m_nextFetchDelayID = this.m_delaySystem.DelayCallback(CatFactUpdateCallback.Create(this), delay, isAffectedByTimeDilation);
  }

  public func FetchCatFact() {
    if this.m_settings.enabled {
      let apiUrl: String;
      if this.m_settings.useDogFacts {
        apiUrl = "https://dogapi.dog/api/v2/facts?limit=1";
      } else {
        apiUrl = "https://catfact.ninja/fact";
      }
      let callback = HttpCallback.Create(this, n"OnCatFactReceived");
      AsyncHttpClient.Get(callback, apiUrl);
      this.ScheduleNextCheck(); // Assume this schedules the next fetch
    }
  }

  public func ResetCycleAndFetchImmediately() -> Void {
    if Equals(this.m_nextFetchDelayID, GetInvalidDelayID()) {
      // FTLog("ResetCycleAndFetchImmediately: Cancelling callback");
      this.m_delaySystem.CancelCallback(this.m_nextFetchDelayID);
      this.m_nextFetchDelayID = GetInvalidDelayID();
    }
    // FTLog("ResetCycleAndFetchImmediately: Fetching cat fact");
    this.FetchCatFact();
  }

private cb func OnCatFactReceived(response: ref<HttpResponse>) {
  if !Equals(response.GetStatus(), HttpStatus.OK) {
    // FTLog(s"HTTP request failed with status: \(response.GetStatus())");
    return;
  }

  let json = response.GetJson();
  if !IsDefined(json) || !json.IsObject() {
    // FTLog("Invalid JSON response");
    return;
  }

  let fact: String;
  if this.m_settings.useDogFacts {
    // Parse dog fact from nested structure
    let dataVariant = (json as JsonObject).GetKey("data");
    if IsDefined(dataVariant) && dataVariant.IsArray() {
      let dataArray = dataVariant as JsonArray;
      if dataArray.GetSize() > 0u {
        let firstFactVariant = dataArray.GetItem(0u);
        if IsDefined(firstFactVariant) && firstFactVariant.IsObject() {
          let factObject = firstFactVariant as JsonObject;
          let attributesVariant = factObject.GetKey("attributes");
          if IsDefined(attributesVariant) && attributesVariant.IsObject() {
            let attributesObject = attributesVariant as JsonObject;
            let bodyVariant = attributesObject.GetKey("body");
            if IsDefined(bodyVariant) {
              fact = bodyVariant.ToString();
              if StrLen(fact) >= 2 && StrBeginsWith(fact, "\"") && StrEndsWith(fact, "\"") {
                fact = StrMid(fact, 1, StrLen(fact) - 2);
              }
            }
          }
        }
      }
    }
  } else {
    // Parse cat fact from flat structure
    fact = (json as JsonObject).GetKeyString("fact");
  }
  // FTLog(s"Fact: \(fact)");
  if StrLen(fact) > 0 {
    // Keep only the latest fact
    ArrayClear(this.m_catFacts);              // Clear the array
    ArrayPush(this.m_catFacts, fact);         // Add the new fact
    CatFactJournalManager.GetCatFactJournalManager().SendCatFacts(this.m_catFacts);

    this.m_messageCounterService.IncrementMessageCount();
    let messageCount = this.m_messageCounterService.GetMessageCount();

    if messageCount == 25 {
      CatFactJournalManager.GetCatFactJournalManager().SendEndorsementMessage();
    }
  } else {
    // FTLog("No fact extracted from response");
  }
}
}

// Journal manager to display cat facts and intro message
public class CatFactJournalManager extends ScriptableService {
  private let m_journalToken: ref<ResourceToken>;

  public static func IsReleaseBuild() -> Bool {
    return true;
  }

  private cb func OnLoad() {
    let depot = GameInstance.GetResourceDepot();
    this.m_journalToken = depot.LoadResource(r"base\\journal\\cooked_journal.journal");
    GameInstance.GetCallbackSystem().RegisterCallback(n"Session/Ready", this, n"OnSessionReady");
  }

  public static func GetCatFactJournalManager() -> ref<CatFactJournalManager> {
    return GameInstance.GetScriptableServiceContainer().GetService(n"CatFactJournalManager") as CatFactJournalManager;
  }

  public func SendIntroMessage() -> Void {
    let journalManager = GameInstance.GetJournalManager(GetGameInstance());
    let success = journalManager.ChangeEntryState("contacts/CatFacts", "gameJournalContact", gameJournalEntryState.Active, JournalNotifyOption.Notify);
    let convSuccess = journalManager.ChangeEntryState("contacts/CatFacts/intro", "JournalPhoneConversation", gameJournalEntryState.Active, JournalNotifyOption.Notify);
    let msgSuccess = journalManager.ChangeEntryState("contacts/CatFacts/intro/installmessage", "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
    GameInstance.GetTransactionSystem(GetGameInstance()).RemoveMoney(GetPlayer(GetGameInstance()), 100, n"money");
    // // FTLog(s"Intro: Contact 'contacts/CatFacts': \(success), Conv: \(convSuccess), Msg: \(msgSuccess)");
    
    // Set the fact to indicate the intro message has been sent
    let questsSystem = GameInstance.GetQuestsSystem(GetGameInstance());
    questsSystem.SetFactStr("mchedda_catfacts_contact_added", 1);
  }

public func SendCatFacts(facts: array<String>) -> Void {
  let journalManager = GameInstance.GetJournalManager(GetGameInstance());
  
  // Deactivate the conversation to reset its state
  journalManager.ChangeEntryState("contacts/CatFacts/messages", "JournalPhoneConversation", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
  
  // Activate the conversation with notification
  let convSuccess = journalManager.ChangeEntryState("contacts/CatFacts/messages", "JournalPhoneConversation", gameJournalEntryState.Active, JournalNotifyOption.Notify);
  // // FTLog(s"Activated conversation 'contacts/CatFacts/messages': \(convSuccess)");

  if IsDefined(this.m_journalToken) && this.m_journalToken.IsLoaded() {
    let journalResource = this.m_journalToken.GetResource() as gameJournalResource;
    if IsDefined(journalResource) {
      let i = 0;
      while i < ArraySize((journalResource.entry as gameJournalRootFolderEntry).entries) {
        let rootFolderEntry = (journalResource.entry as gameJournalRootFolderEntry).entries[i] as gameJournalPrimaryFolderEntry;
        if Equals(rootFolderEntry.id, "contacts") {
          let j = 0;
          while j < ArraySize(rootFolderEntry.entries) {
            if Equals((rootFolderEntry.entries[j] as JournalContact).id, "CatFacts") {
              let conversation = (rootFolderEntry.entries[j] as JournalContact).entries[0] as JournalPhoneConversation;
              if IsDefined(conversation) {
                let messagePath = "contacts/CatFacts/messages/message0";
                if ArraySize(facts) > 0 {
                  // Deactivate the message to reset its state
                  journalManager.ChangeEntryState(messagePath, "gameJournalPhoneMessage", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
                  // Update the message text
                  let message = conversation.entries[0] as JournalPhoneMessage;
                  if IsDefined(message) {
                    message.text = ToLocalizationString(facts[0]);
                  }
                  // Activate the message with notification
                  let msgSuccess = journalManager.ChangeEntryState(messagePath, "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
                  // // FTLog(s"Activated message '\(messagePath)': \(msgSuccess)");
                } else {
                  let msgSuccess = journalManager.ChangeEntryState(messagePath, "gameJournalPhoneMessage", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
                  // // FTLog(s"Deactivated message '\(messagePath)': \(msgSuccess)");
                }
              }
            }
            j += 1;
          }
        }
        i += 1;
      }
    }
  } else {
    // // FTLog("Journal resource not ready or failed to load");
  }
}

  public func SendEndorsementMessage() -> Void {
    let journalManager = GameInstance.GetJournalManager(GetGameInstance());
    let convSuccess = journalManager.ChangeEntryState("contacts/CatFacts/special", "JournalPhoneConversation", gameJournalEntryState.Active, JournalNotifyOption.Notify);
    let msgSuccess = journalManager.ChangeEntryState("contacts/CatFacts/special/endorsement", "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
    // // FTLog(s"Endorsement: Conv: \(convSuccess), Msg: \(msgSuccess)");
  }
}