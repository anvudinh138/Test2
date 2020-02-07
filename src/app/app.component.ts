import { element } from 'protractor';
import { UserInfo } from './models/app.model';
import { AppService } from './services/app.service';
import { Component, OnInit, ElementRef } from '@angular/core';

@Component({
  selector: 'app-root',
  templateUrl: './app.component.html',
  styleUrls: ['./app.component.scss']
})
export class AppComponent implements OnInit {
  listUserDisplay: UserInfo[] = [];
  remainUser: UserInfo[] = [];
  isShowPanel = false;
  userSelected: UserInfo;

  constructor(
    private appService: AppService,
  ) { }

  ngOnInit() {
    this.getAllDataUser();
  }

  onClickSquare(user: UserInfo) {
    user.timesClicked++;
    user.updateColorByTimeClicked();
    this.sortListUser();
    this.isShowPanel = true;
    this.userSelected = user;
  }

  getAllDataUser() {
    this.appService.getAllDataUser().subscribe((users: UserInfo[]) => {
      this.listUserDisplay = users.splice(0, 6); // default 6 items
      this.remainUser = users;
    });
  }

  onLoadMore() {
    if (this.remainUser.length !== 0) {
      this.listUserDisplay = this.listUserDisplay.concat(this.remainUser.splice(0, 10));
    }
  }

  sortListUser() {
    this.listUserDisplay.sort((a, b) => b.timesClicked - a.timesClicked);
  }
}
