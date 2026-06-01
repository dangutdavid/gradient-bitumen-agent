import { createElement } from "lwc";
import GbSalesAgent from "c/gbSalesAgent";
import advance from "@salesforce/apex/AgentConversationController.advance";

jest.mock(
  "@salesforce/apex/AgentConversationController.advance",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

function createComponent(props = {}) {
  const el = createElement("c-gb-sales-agent", { is: GbSalesAgent });
  Object.assign(el, props);
  document.body.appendChild(el);
  return el;
}

function typeAndSend(el, text) {
  const ta = el.shadowRoot.querySelector("lightning-textarea");
  ta.value = text;
  ta.dispatchEvent(new CustomEvent("change"));
  // Before a summary is shown, the only lightning-button is the Send button.
  el.shadowRoot.querySelector("lightning-button").click();
}

const flush = () => Promise.resolve().then(() => Promise.resolve());

afterEach(() => {
  while (document.body.firstChild) {
    document.body.removeChild(document.body.firstChild);
  }
  jest.clearAllMocks();
});

describe("c-gb-sales-agent", () => {
  it("greets differently on the Account page vs the utility bar", () => {
    const onPage = createComponent({ recordId: "001000000000001AAA" });
    const utility = createComponent();
    expect(
      onPage.shadowRoot.querySelector(".gb-msg_agent").textContent
    ).toContain("this account");
    expect(
      utility.shadowRoot.querySelector(".gb-msg_agent").textContent
    ).toContain("including the account");
  });

  it("passes pageAccountId from recordId to the controller", async () => {
    advance.mockResolvedValue({
      status: "NEEDS_INPUT",
      message: "Need more",
      missingFields: ["Order: Start Date"],
      stateJson: '{"phase":"COLLECTING"}'
    });
    const el = createComponent({ recordId: "001000000000001AAA" });
    typeAndSend(el, "30 MT commercial");
    await flush();
    expect(advance).toHaveBeenCalled();
    expect(advance.mock.calls[0][0].pageAccountId).toBe("001000000000001AAA");
    expect(advance.mock.calls[0][0].userText).toBe("30 MT commercial");
  });

  it("renders missing fields on NEEDS_INPUT", async () => {
    advance.mockResolvedValue({
      status: "NEEDS_INPUT",
      message: "I need a couple of things.",
      missingFields: ["Opportunity: Close Date", "Order: Start Date"],
      stateJson: '{"phase":"COLLECTING"}'
    });
    const el = createComponent({ recordId: "001000000000001AAA" });
    typeAndSend(el, "commercial 30 MT of bitumen");
    await flush();
    const items = el.shadowRoot.querySelectorAll(".gb-missing li");
    expect(items.length).toBe(2);
    expect(el.shadowRoot.querySelector(".gb-missing").textContent).toContain(
      "Close Date"
    );
  });

  it("shows the summary card with Proceed/Cancel on NEEDS_CONFIRM", async () => {
    advance.mockResolvedValue({
      status: "NEEDS_CONFIRM",
      message: "Proceed?",
      summaryJson: JSON.stringify({
        accountName: "Acme Ltd",
        typeOfLoad: "Commercial",
        line: {
          QuantityMT_DKL__c: 30,
          PricePerMT_DKL__c: 450000,
          Location_DKL__c: "Kano",
          CustomerType_DKL__c: "Credit"
        },
        opportunity: { CloseDate: "2026-06-30" },
        order: { EffectiveDate: "2026-06-01" }
      }),
      stateJson: '{"phase":"AWAITING_CONFIRM"}'
    });
    const el = createComponent({ recordId: "001000000000001AAA" });
    typeAndSend(el, "commercial 30 MT of bitumen at 450000, deliver to Kano");
    await flush();

    const summary = el.shadowRoot.querySelector(".gb-summary");
    expect(summary).not.toBeNull();
    expect(summary.textContent).toContain("Acme Ltd");
    expect(summary.textContent).toContain("Kano");
    expect(
      el.shadowRoot.querySelectorAll(".gb-summary lightning-button").length
    ).toBe(2);
  });

  it("Proceed sends yes, auto-continues into submit, and shows result links", async () => {
    advance
      .mockResolvedValueOnce({
        status: "NEEDS_CONFIRM",
        message: "Proceed?",
        summaryJson: JSON.stringify({
          accountName: "Acme Ltd",
          typeOfLoad: "Commercial",
          line: {},
          opportunity: {},
          order: {}
        }),
        stateJson: '{"phase":"AWAITING_CONFIRM"}'
      })
      .mockResolvedValueOnce({
        status: "OK",
        message: "Records created. Submitting…",
        autoContinue: true,
        recordId: "a08000000000001AAA",
        stateJson: '{"phase":"PENDING_SUBMIT"}'
      })
      .mockResolvedValueOnce({
        status: "OK",
        message: "Done. Submitted for approval.",
        summaryJson: JSON.stringify({
          submitted: true,
          opportunity: { id: "006", url: "https://x/006" },
          order: { id: "801", url: "https://x/801" },
          loadingAdvice: { id: "a08", url: "https://x/a08" },
          line: { id: "a07", url: "https://x/a07" }
        }),
        stateJson: '{"phase":"COLLECTING"}'
      });

    const el = createComponent({ recordId: "001000000000001AAA" });
    typeAndSend(el, "commercial 30 MT of bitumen at 450000, deliver to Kano");
    await flush();

    const proceed = [
      ...el.shadowRoot.querySelectorAll(".gb-summary lightning-button")
    ].find((b) => b.label === "Proceed");
    proceed.click();
    await flush();
    await flush();

    expect(advance).toHaveBeenCalledTimes(3);
    expect(advance.mock.calls[1][0].userText).toBe("yes");
    const links = el.shadowRoot.querySelectorAll(".gb-links a");
    expect(links.length).toBe(4);
    expect(el.shadowRoot.querySelector(".gb-links").textContent).toContain(
      "Loading Advice"
    );
  });

  it("surfaces controller errors gracefully", async () => {
    advance.mockRejectedValue({ body: { message: "boom" } });
    const el = createComponent({ recordId: "001000000000001AAA" });
    typeAndSend(el, "do the thing");
    await flush();
    const agentMsgs = [...el.shadowRoot.querySelectorAll(".gb-msg_agent")].map(
      (n) => n.textContent
    );
    expect(agentMsgs.some((t) => t.includes("boom"))).toBe(true);
  });
});
