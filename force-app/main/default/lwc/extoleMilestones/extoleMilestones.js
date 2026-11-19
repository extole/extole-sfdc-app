import { LightningElement, api } from 'lwc';

// A person's journey steps as a list of dots: green when done, red when the
// event failed Extole's quality checks, hollow when not reached yet.
export default class ExtoleMilestones extends LightningElement {
    @api milestones = [];
}
