import { LightningElement, api } from "lwc";
import advance from "@salesforce/apex/AgentConversationController.advance";

/**
 * Conversational sales agent chat panel.
 * - Holds the conversation state in memory (no localStorage/sessionStorage) and passes it
 *   in/out of AgentConversationController.advance each turn.
 * - On an Account record page, recordId is the Account Id and is sent as pageAccountId so the
 *   agent skips the account-name question. On the utility bar there is no recordId, so the
 *   agent asks for the account name.
 */
export default class GbSalesAgent extends LightningElement {
  @api recordId; // Account Id on the Account record page; undefined on the utility bar

  messages = [];
  inputValue = "";
  isBusy = false;
  missingFields = [];
  summaryItems = [];
  resultLinks = [];
  showSummary = false;

  conversationState = null; // stateJson echoed by the controller (in memory only)
  _seq = 0;

  connectedCallback() {
    this.addAgent(
      this.recordId
        ? 'Hi! Describe the loading advice for this account — e.g. "commercial, 30 MT of Bitumen 60/70 at NGN 450,000/MT, deliver to Kano".'
        : 'Hi! Tell me what to create, including the account — e.g. "commercial loading advice for Acme Ltd — 30 MT of Bitumen 60/70 at NGN 450,000/MT, deliver to Kano".'
    );
  }

  get hasMissing() {
    return this.missingFields && this.missingFields.length > 0;
  }
  get hasLinks() {
    return this.resultLinks && this.resultLinks.length > 0;
  }
  get inputDisabled() {
    return this.isBusy;
  }

  // ---- input handlers ----
  handleInput(event) {
    this.inputValue = event.target.value;
  }
  handleKeyup(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      this.handleSend();
    }
  }
  handleSend() {
    const text = (this.inputValue || "").trim();
    if (!text || this.isBusy) {
      return;
    }
    this.addUser(text);
    this.inputValue = "";
    this.runTurn(text);
  }
  handleProceed() {
    this.addUser("Yes");
    this.runTurn("yes");
  }
  handleCancel() {
    this.addUser("No");
    this.runTurn("no");
  }

  // ---- turn loop ----
  async runTurn(text) {
    this.isBusy = true;
    this.showSummary = false;
    this.missingFields = [];
    try {
      let res = await advance({
        userText: text,
        stateJson: this.conversationState,
        pageAccountId: this.recordId
      });
      this.applyResult(res);
      // Commit and submit are separate transactions; auto-continue into the submit step.
      if (res && res.autoContinue) {
        res = await advance({
          userText: "",
          stateJson: this.conversationState,
          pageAccountId: this.recordId
        });
        this.applyResult(res);
      }
    } catch (error) {
      const msg =
        error && error.body && error.body.message
          ? error.body.message
          : "unexpected error";
      this.addAgent("Sorry — something went wrong: " + msg);
    } finally {
      this.isBusy = false;
    }
  }

  applyResult(res) {
    if (!res) {
      return;
    }
    this.conversationState = res.stateJson;
    if (res.message) {
      this.addAgent(res.message);
    }
    this.missingFields =
      res.status === "NEEDS_INPUT" && res.missingFields
        ? res.missingFields
        : [];
    if (res.status === "NEEDS_CONFIRM" && res.summaryJson) {
      this.summaryItems = this.buildSummary(res.summaryJson);
      this.showSummary = true;
    }
    if (res.status === "OK" && res.summaryJson && !res.autoContinue) {
      this.resultLinks = this.buildLinks(res.summaryJson);
    }
  }

  // ---- message helpers ----
  addUser(text) {
    this.messages = [
      ...this.messages,
      { id: ++this._seq, text, cssClass: "gb-msg gb-msg_user" }
    ];
  }
  addAgent(text) {
    this.messages = [
      ...this.messages,
      { id: ++this._seq, text, cssClass: "gb-msg gb-msg_agent" }
    ];
  }

  // ---- summary / links parsing ----
  buildSummary(summaryJson) {
    try {
      const s = JSON.parse(summaryJson);
      const line = s.line || {};
      const opp = s.opportunity || {};
      const order = s.order || {};
      const rows = [
        ["Account", s.accountName],
        ["Type of Load", s.typeOfLoad],
        ["Quantity (MT)", this.str(line.QuantityMT_DKL__c)],
        ["Price (N/MT)", this.str(line.PricePerMT_DKL__c)],
        ["Location", line.Location_DKL__c],
        ["Customer Type", line.CustomerType_DKL__c],
        ["Opp Close Date", opp.CloseDate],
        ["Order Start Date", order.EffectiveDate]
      ];
      return rows
        .filter((r) => r[1] !== undefined && r[1] !== null && r[1] !== "")
        .map((r, i) => ({ id: i, k: r[0], v: r[1] }));
    } catch {
      return [];
    }
  }

  buildLinks(summaryJson) {
    try {
      const s = JSON.parse(summaryJson);
      const out = [];
      const add = (label, obj) => {
        if (obj && obj.url) {
          out.push({ id: label, label, url: obj.url });
        }
      };
      add("Opportunity", s.opportunity);
      add("Order", s.order);
      add("Loading Advice", s.loadingAdvice);
      add("Loading Advice Line", s.line);
      return out;
    } catch {
      return [];
    }
  }

  str(v) {
    return v === undefined || v === null ? v : String(v);
  }
}
