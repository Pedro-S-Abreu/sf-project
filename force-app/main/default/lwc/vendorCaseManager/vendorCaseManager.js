import { LightningElement, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { updateRecord } from "lightning/uiRecordApi";
import getCaseItems from "@salesforce/apex/VendorCaseController.getCaseItems";
import createCaseItem from "@salesforce/apex/VendorCaseController.createCaseItem";
import updateCaseItem from "@salesforce/apex/VendorCaseController.updateCaseItem";
import deleteCaseItem from "@salesforce/apex/VendorCaseController.deleteCaseItem";
import getDefaultPricebookEntry from "@salesforce/apex/VendorCaseController.getDefaultPricebookEntry";
import CASE_ID from "@salesforce/schema/Case.Id";
import CASE_STATUS from "@salesforce/schema/Case.Status";
import { subscribe, unsubscribe, onError } from "lightning/empApi";

export default class VendorCaseManager extends LightningElement {
    @track selectedCaseId;
    @track caseItems = [];
    @track isLoading = false;
    @track showToast = false;
    @track showModal = false;
    @track modalTitle = "Add Case Item";
    @track modalItemId;
    @track modalProductId;
    @track modalQuantity = 1;
    @track isProductLocked = false;
    @track isProcessing = false;

    channelName = "/data/Vendor_Callout_Log__ChangeEvent";
    subscription = {};

    itemColumns = [
        { label: "Product Name", fieldName: "ProductName" },
        { label: "Quantity", fieldName: "Quantity__c", type: "number" },
        {
            type: "action",
            typeAttributes: {
                rowActions: [
                    { label: "Edit", name: "edit" },
                    { label: "Delete", name: "delete" }
                ],
                menuAlignment: "right"
            }
        }
    ];

    connectedCallback() {
        this.handleSubscribe();
        onError((error) => {
            console.error("EMP API error:", JSON.stringify(error));
        });
    }

    disconnectedCallback() {
        this.handleUnsubscribe();
    }

    handleSubscribe() {
        const callback = (response) => {
            const eventData = response.data.payload.ChangeEventHeader;
            const recordData = response.data.payload;
            if (
                recordData.Case__c === this.selectedCaseId &&
                this.isProcessing &&
                eventData.changeType === "CREATE"
            ) {
                if (recordData.Is_Successful__c) {
                    this.showSuccessToast("Submission successful!", true);

                    this.loadCaseItems();
                    this.selectedCaseId = null;
                    this.caseItems = [];
                } else {
                    this.showErrorToast(
                        "Submission Failed",
                        "Vendor processing encountered an error."
                    );
                }
                this.isProcessing = false;
            }
        };
        subscribe(this.channelName, -1, callback).then((response) => {
            this.subscription = response;
        });
    }

    handleUnsubscribe() {
        unsubscribe(this.subscription, (response) => {
            console.log("Unsubscribed from channel:", this.channelName);
        });
    }

    handleCaseChange(event) {
        this.selectedCaseId = event.detail.recordId;
        if (this.selectedCaseId) {
            this.loadCaseItems();
        } else {
            this.caseItems = [];
        }
    }

    loadCaseItems() {
        this.isLoading = true;
        getCaseItems({ caseId: this.selectedCaseId })
            .then((result) => {
                this.caseItems = result.map((item) => ({
                    id: item.Id,
                    ProductName: item.Product__r?.Name || "Unknown",
                    ProductId: item.Product__r?.Id,
                    Quantity__c: item.Quantity__c
                }));
            })
            .catch((error) => {
                this.showErrorToast(
                    "Error loading Case Items",
                    error.body?.message
                );
                this.caseItems = [];
                this.addDefaultItem();
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;
        if (actionName === "edit") {
            this.openEditItemModal(row);
        } else if (actionName === "delete") {
            this.deleteItem(row.id);
        }
    }

    openAddItemModal() {
        this.modalTitle = "Add Case Item";
        this.modalItemId = null;
        this.modalQuantity = 1;
        this.isProductLocked = false;

        getDefaultPricebookEntry()
            .then((pricebookEntry) => {
                this.modalProductId = pricebookEntry.Product2Id;
            })
            .catch((error) => {
                this.showErrorToast(
                    "Error loading default product",
                    error.body?.message
                );
                this.modalProductId = null;
            });

        this.showModal = true;
    }

    openEditItemModal(row) {
        this.modalTitle = "Edit Case Item";
        this.modalItemId = row.id;
        this.modalProductId = row.ProductId;
        this.modalQuantity = row.Quantity__c;
        this.isProductLocked = true;
        this.showModal = true;
    }

    closeModal() {
        this.showModal = false;
    }

    handleProductChange(event) {
        if (!this.isProductLocked) {
            this.modalProductId = event.detail.recordId;
        }
    }

    handleQuantityChange(event) {
        this.modalQuantity = event.target.value;
    }

    saveItem() {
        this.isLoading = true;
        if (this.modalItemId) {
            updateCaseItem({
                itemId: this.modalItemId,
                productId: this.modalProductId,
                quantity: this.modalQuantity
            })
                .then(() => {
                    this.loadCaseItems();
                    this.showSuccessToast("Case Item updated successfully");
                    this.closeModal();
                })
                .catch((error) => {
                    this.showErrorToast(
                        "Error updating Case Item",
                        error.body?.message
                    );
                })
                .finally(() => {
                    this.isLoading = false;
                });
        } else {
            createCaseItem({
                caseId: this.selectedCaseId,
                productId: this.modalProductId,
                quantity: this.modalQuantity
            })
                .then(() => {
                    this.loadCaseItems();
                    this.showSuccessToast("Case Item added successfully");
                    this.closeModal();
                })
                .catch((error) => {
                    this.showErrorToast(
                        "Error adding Case Item",
                        error.body?.message
                    );
                })
                .finally(() => {
                    this.isLoading = false;
                });
        }
    }

    deleteItem(itemId) {
        this.isLoading = true;
        deleteCaseItem({ itemId: itemId })
            .then(() => {
                this.caseItems = this.caseItems.filter(
                    (item) => item.id !== itemId
                );
                this.showSuccessToast("Case Item deleted successfully");
            })
            .catch((error) => {
                this.showErrorToast(
                    "Error deleting Case Item",
                    error.body?.message
                );
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleSubmit() {
        this.isProcessing = true;
        this.showPendingToast("Submitting to Vendor...", true);

        const fields = {};
        fields[CASE_ID.fieldApiName] = this.selectedCaseId;
        fields[CASE_STATUS.fieldApiName] = "Submit to Vendor";
        updateRecord({ fields })
            .then(() => {
                setTimeout(() => {
                    if (this.isProcessing) {
                        this.showErrorToast(
                            "Submission Timeout",
                            "No response from vendor after 30 seconds."
                        );
                        this.isProcessing = false;
                    }
                }, 30000);
            })
            .catch((error) => {
                this.showErrorToast(
                    "Error updating Case status",
                    error.body?.message
                );
                this.isProcessing = false;
            });
    }

    get isSaveDisabled() {
        return !this.modalProductId || this.modalQuantity < 1;
    }

    showPendingToast(message, sticky = false) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: "Pending",
                message: message,
                variant: "info",
                mode: sticky ? "sticky" : "dismissable"
            })
        );
    }

    showSuccessToast(message, sticky = false) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: "Success",
                message: message,
                variant: "success",
                mode: sticky ? "sticky" : "dismissable"
            })
        );
    }

    showErrorToast(title, message, sticky = false) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: "error",
                mode: sticky ? "sticky" : "dismissable"
            })
        );
    }
}
