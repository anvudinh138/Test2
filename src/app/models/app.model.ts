import { arrColorBackground } from './../constants/colorSquares';
export class UserInfo {
    id: number;
    title: string;
    body: string;
    timesClicked: number;
    backgroundColor: string;

    constructor(res) {
        this.id = res.id;
        this.title = res.title;
        this.body = res.body;
        this.timesClicked = 0;
        this.backgroundColor = arrColorBackground[this.timesClicked]; // color default
    }

    updateColorByTimeClicked() {
        this.backgroundColor = arrColorBackground[this.timesClicked] || arrColorBackground[arrColorBackground.length - 1];
    }
}
