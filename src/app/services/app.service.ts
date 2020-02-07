import { UserInfo } from './../models/app.model';
import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { map } from 'rxjs/operators';

@Injectable()
export class AppService {
    mockUrl = 'https://jsonplaceholder.typicode.com/posts';
    constructor(private http: HttpClient) { }

    getAllDataUser(): Observable<UserInfo[]> {
        return this.http.get<any>(this.mockUrl)
            .pipe(map((res: UserInfo[]) => res.map(item => new UserInfo(item))));
    }
}
